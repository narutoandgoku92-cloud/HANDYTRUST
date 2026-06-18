/**
 * HandyTrust Cloud Functions
 *
 * Handles:
 *  1. Paystack webhook → escrow lock
 *  2. Auto-release escrow after 48h (no customer action)
 *  3. Artisan stats update on job completion
 *  4. FCM push notifications on job state changes
 *  5. Dispute escalation alerts to admin
 */

const { onRequest, onCall } = require('firebase-functions/v2/https');
const { onDocumentUpdated, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('crypto');
const axios = require('axios');
const { GoogleGenerativeAI } = require('@google/generative-ai');

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// ─── Paystack Webhook ─────────────────────────────────────────────────────────
exports.paystackWebhook = onRequest(
  { secrets: ['PAYSTACK_SECRET_KEY'] },
  async (req, res) => {
    // Verify Paystack signature
    const hash = crypto
      .createHmac('sha512', process.env.PAYSTACK_SECRET_KEY)
      .update(JSON.stringify(req.body))
      .digest('hex');

    if (hash !== req.headers['x-paystack-signature']) {
      console.error('Invalid Paystack signature');
      return res.status(400).send('Invalid signature');
    }

    const event = req.body;

    if (event.event === 'charge.success') {
      const { reference, metadata } = event.data;
      const { jobId } = metadata;

      if (!jobId) {
        console.error('No jobId in Paystack metadata', metadata);
        return res.status(200).send('OK'); // Don't retry
      }

      try {
        await _lockEscrow(jobId, reference);
        console.log(`Escrow locked for job ${jobId} ref ${reference}`);
      } catch (err) {
        console.error('lockEscrow failed', err);
        return res.status(500).send('Internal error');
      }
    }

    return res.status(200).send('OK');
  }
);

async function _lockEscrow(jobId, reference) {
  const jobRef = db.collection('jobs').doc(jobId);
  const paymentSnap = await db
    .collection('payments')
    .where('jobId', '==', jobId)
    .where('paystackReference', '==', reference)
    .limit(1)
    .get();

  await db.runTransaction(async (tx) => {
    const job = await tx.get(jobRef);
    if (!job.exists) throw new Error(`Job ${jobId} not found`);

    const status = job.data().status;
    if (status !== 'paymentPending') {
      throw new Error(`Cannot lock escrow: job is in state ${status}`);
    }

    const now = admin.firestore.Timestamp.now();
    const autoRelease = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 48 * 60 * 60 * 1000)
    );

    tx.update(jobRef, {
      status: 'escrowLocked',
      paymentReference: reference,
      escrowLockedAt: now,
      autoReleaseAt: autoRelease,
    });

    if (!paymentSnap.empty) {
      tx.update(paymentSnap.docs[0].ref, {
        status: 'escrowHeld',
        paidAt: now,
      });
    }
  });

  await _sendNotification(jobId, 'escrowLocked');
}

// ─── Auto-release Escrow (runs every hour) ────────────────────────────────────
exports.autoReleaseEscrow = onSchedule('every 1 hours', async () => {
  const now = admin.firestore.Timestamp.now();

  const snap = await db
    .collection('jobs')
    .where('status', '==', 'submitted')
    .where('autoReleaseAt', '<=', now)
    .get();

  const releases = snap.docs.map((doc) =>
    _releaseEscrow(doc.id, 'auto-release: customer did not respond within 48h')
  );

  await Promise.allSettled(releases);
  console.log(`Auto-released ${releases.length} jobs`);
});

async function _releaseEscrow(jobId, reason) {
  const jobRef = db.collection('jobs').doc(jobId);
  const job = await jobRef.get();
  if (!job.exists) return;

  const { artisanId, paymentReference, agreedAmount } = job.data();

  // Mark job completed
  await jobRef.update({
    status: 'completed',
    completedAt: admin.firestore.Timestamp.now(),
    autoReleaseReason: reason,
  });

  // Update payment status
  if (paymentReference) {
    const paySnap = await db
      .collection('payments')
      .where('jobId', '==', jobId)
      .limit(1)
      .get();

    if (!paySnap.empty) {
      await paySnap.docs[0].ref.update({
        status: 'released',
        releasedAt: admin.firestore.Timestamp.now(),
      });
    }
  }

  // Update artisan stats + trust score
  if (artisanId) {
    await _recordJobOutcome(artisanId, 'completed');
  }

  console.log(`Released escrow for job ${jobId}: ${reason}`);
}

// ─── On Job Completed — update artisan stats + trust score ───────────────────
exports.onJobCompleted = onDocumentUpdated('jobs/{jobId}', async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before.status === after.status) return;

  if (after.status === 'completed' && after.artisanId) {
    await _recordJobOutcome(after.artisanId, 'completed');
    await _sendNotification(event.params.jobId, 'completed');
  }

  if (after.status === 'cancelled' && after.artisanId) {
    // Only counts cancellations after an artisan was matched — a job
    // cancelled while still 'requested' never reached an artisan.
    await _recordJobOutcome(after.artisanId, 'cancelled');
  }

  if (after.status === 'disputed') {
    if (after.artisanId) await _adjustDisputeCount(after.artisanId, 1);
    await _alertAdminDispute(event.params.jobId, after);
    await _sendNotification(event.params.jobId, 'disputed');
  }

  if (after.status === 'resolved' && after.artisanId) {
    await _adjustDisputeCount(after.artisanId, -1);
  }

  if (after.status === 'escrowLocked') {
    await _sendNotification(event.params.jobId, 'escrowLocked');
  }

  if (after.status === 'submitted') {
    await _sendNotification(event.params.jobId, 'submitted');
  }
});

// ─── Trust score computation ──────────────────────────────────────────────────
// Composite score 0-100, 5 weighted components. New artisans (no ratings
// yet) start at a neutral rating component so a single early job can't
// swing the score to extremes.
//
// 40% Customer rating    — 5.0 stars = 100, no ratings yet = neutral 20/40.
// 25% Completed jobs     — absolute volume, 0 jobs = 0, 50+ jobs = full marks.
//                           (Not a ratio — a brand-new artisan with 2/2 jobs
//                           shouldn't outrank a proven one with 40/45.)
// 15% Verification       — unverified=0, id_submitted=50, id_verified/trusted=100.
// 10% Response time      — <=15min=100, <=30min=80, <=60min=60, decaying further.
// 10% Dispute history    — no open disputes=100, each one -25.
const TRUST_VERIFICATION_POINTS = {
  unverified: 0,
  id_submitted: 50,
  id_verified: 100,
  trusted: 100,
};

function _trustResponseTimePoints(minutes) {
  if (minutes <= 15) return 100;
  if (minutes <= 30) return 80;
  if (minutes <= 60) return 60;
  if (minutes <= 120) return 40;
  return 20;
}

function _computeTrustScore(stats) {
  const rating = stats.rating || 0;
  const totalRatings = stats.totalRatings || 0;
  const completedJobs = stats.completedJobs || 0;
  const verificationStatus = stats.verificationStatus || 'unverified';
  const responseTimeMinutes = stats.responseTimeMinutes ?? 30;
  const openDisputeCount = stats.openDisputeCount || 0;

  const ratingScore = (totalRatings > 0 ? (rating / 5) * 100 : 50) * 0.40;
  const jobsScore = (Math.min(completedJobs, 50) / 50) * 100 * 0.25;
  const verificationScore =
    (TRUST_VERIFICATION_POINTS[verificationStatus] ?? 0) * 0.15;
  const responseScore = _trustResponseTimePoints(responseTimeMinutes) * 0.10;
  const disputeScore = Math.max(0, 100 - openDisputeCount * 25) * 0.10;

  const score = ratingScore + jobsScore + verificationScore + responseScore + disputeScore;
  return Math.max(0, Math.min(100, Math.round(score * 10) / 10));
}

// Records a completed/cancelled job against an artisan's lifetime stats and
// recomputes their trust score in the same transaction — single source of
// truth for both job-outcome counters and the derived score.
async function _recordJobOutcome(artisanId, outcome) {
  const artRef = db.collection('artisans').doc(artisanId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(artRef);
    if (!snap.exists) return;
    const data = snap.data();

    const totalJobs = (data.totalJobs || 0) + 1;
    const completedJobs = (data.completedJobs || 0) + (outcome === 'completed' ? 1 : 0);
    const cancelledJobsCount = (data.cancelledJobsCount || 0) + (outcome === 'cancelled' ? 1 : 0);
    const cancellationRatePercent =
      totalJobs > 0 ? Math.round((cancelledJobsCount / totalJobs) * 1000) / 10 : 0;

    const trustScore = _computeTrustScore({
      ...data,
      totalJobs,
      completedJobs,
      cancellationRatePercent,
    });

    tx.update(artRef, {
      totalJobs,
      completedJobs,
      cancelledJobsCount,
      cancellationRatePercent,
      trustScore,
    });
  });
}

// Adjusts open-dispute count (+1 when raised, -1 when resolved) and
// recomputes trust score in the same transaction.
async function _adjustDisputeCount(artisanId, delta) {
  const artRef = db.collection('artisans').doc(artisanId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(artRef);
    if (!snap.exists) return;
    const data = snap.data();

    const openDisputeCount = Math.max(0, (data.openDisputeCount || 0) + delta);
    const trustScore = _computeTrustScore({ ...data, openDisputeCount });

    tx.update(artRef, { openDisputeCount, trustScore });
  });
}

// ─── On Artisan Rating Changed — keep trust score in sync with reviews ───────
// ReviewScreen writes rating/totalRatings directly to /artisans (existing,
// pre-dating this Cloud Function). This trigger recomputes trustScore so it
// reflects every new review without adding a parallel write path — the only
// thing it ever writes is trustScore itself, and the guard below stops it
// from re-triggering on its own update.
exports.onArtisanRatingChanged = onDocumentUpdated('artisans/{artisanId}', async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before.rating === after.rating && before.totalRatings === after.totalRatings) {
    return;
  }

  const trustScore = _computeTrustScore(after);
  if (trustScore === after.trustScore) return;

  await db.collection('artisans').doc(event.params.artisanId).update({ trustScore });
});

// ─── On Artisan Verification Changed — keep trust score in sync ─────────────
// VerificationService.approve()/reject() writes verificationStatus directly
// to /artisans (existing). This trigger recomputes trustScore the same way
// onArtisanRatingChanged does for reviews — same guard against re-triggering
// on its own write.
exports.onArtisanVerificationChanged = onDocumentUpdated('artisans/{artisanId}', async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before.verificationStatus === after.verificationStatus) return;

  const trustScore = _computeTrustScore(after);
  if (trustScore === after.trustScore) return;

  await db.collection('artisans').doc(event.params.artisanId).update({ trustScore });
});

// ─── On Dispute Created — alert admin ────────────────────────────────────────
exports.onDisputeCreated = onDocumentCreated('disputes/{disputeId}', async (event) => {
  const dispute = event.data.data();
  console.log('New dispute created:', dispute);

  // Store admin alert
  await db.collection('admin_alerts').add({
    type: 'dispute',
    disputeId: event.params.disputeId,
    jobId: dispute.jobId,
    raisedBy: dispute.raisedBy,
    reason: dispute.reason,
    createdAt: admin.firestore.Timestamp.now(),
    resolved: false,
  });
});

async function _alertAdminDispute(jobId, jobData) {
  await db.collection('admin_alerts').add({
    type: 'dispute_from_job',
    jobId,
    customerId: jobData.customerId,
    artisanId: jobData.artisanId,
    reason: jobData.disputeReason,
    createdAt: admin.firestore.Timestamp.now(),
    resolved: false,
  });
}

// ─── Push Notifications ───────────────────────────────────────────────────────
async function _sendNotification(jobId, eventType) {
  const job = await db.collection('jobs').doc(jobId).get();
  if (!job.exists) return;

  const { customerId, artisanId } = job.data();
  const messages = _buildMessages(eventType, jobId, customerId, artisanId);

  for (const msg of messages) {
    try {
      const tokenDoc = await db
        .collection('fcm_tokens')
        .doc(msg.userId)
        .get();
      const token = tokenDoc.data()?.token;
      if (!token) continue;

      await messaging.send({
        token,
        notification: { title: msg.title, body: msg.body },
        data: { jobId, eventType },
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } },
      });
    } catch (err) {
      console.error(`FCM send failed for ${msg.userId}:`, err.message);
    }
  }
}

function _buildMessages(eventType, jobId, customerId, artisanId) {
  const msgs = {
    escrowLocked: [
      {
        userId: artisanId,
        title: '💰 Payment Secured',
        body: 'Escrow is locked. You can now start work on the job.',
      },
      {
        userId: customerId,
        title: '🔒 Funds Locked in Escrow',
        body: 'Your payment is safe. The artisan will begin work shortly.',
      },
    ],
    submitted: [
      {
        userId: customerId,
        title: '✅ Work Submitted',
        body: 'The artisan has submitted completion. Please review and confirm.',
      },
    ],
    completed: [
      {
        userId: artisanId,
        title: '🎉 Payment Released!',
        body: 'The customer confirmed your work. Funds have been released.',
      },
    ],
    disputed: [
      {
        userId: artisanId,
        title: '⚠️ Dispute Raised',
        body: 'The customer has raised a dispute. Our team will review within 48h.',
      },
    ],
  };
  return msgs[eventType] ?? [];
}

// ─── Verify Paystack Transaction (callable from client) ───────────────────────
exports.verifyPayment = onCall(
  { secrets: ['PAYSTACK_SECRET_KEY'] },
  async (request) => {
    const { reference, jobId } = request.data;
    if (!reference || !jobId) {
      throw new Error('reference and jobId are required');
    }

    const resp = await axios.get(
      `https://api.paystack.co/transaction/verify/${reference}`,
      { headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` } }
    );

    const data = resp.data.data;
    if (data.status === 'success') {
      await _lockEscrow(jobId, reference);
      return { success: true };
    }
    return { success: false, gateway_response: data.gateway_response };
  }
);

// ─── AI Job Assistant (V1 — job-improvement only, callable from client) ──────
// Scope is deliberately narrow: classify category + tighten the description.
// Not a chatbot, not stateful, nothing persisted here — the client decides
// whether to save the suggestion onto the job doc at creation time.
const JOB_CATEGORIES = [
  'Plumbing', 'Electrical', 'Carpentry', 'Painting', 'Cleaning',
  'HVAC / AC Repair', 'Welding', 'Tiling', 'Generator Repair',
  'Home Renovation', 'Security Systems', 'Landscaping', 'Other',
];

const ANALYZE_JOB_PROMPT = `You are a job-classification assistant for HandyTrust, a home-services marketplace in Nigeria.
A customer wrote the job description below, optionally with photos of the problem.

Your task:
1. Pick the single best-matching category from this exact list (return the string exactly as written): ${JOB_CATEGORIES.join(', ')}.
2. Rewrite the description so it is clearer and more complete for an artisan to quote accurately. Only use facts the customer stated or that are visibly true in the photos — never invent measurements, quantities, brands, or causes that weren't given.
3. Give a confidence score from 0.0 to 1.0 for the category match. If the description is vague, ambiguous, or could fit more than one category, lower the confidence instead of guessing.

Respond with JSON only, matching this exact shape:
{"suggestedCategory": string, "confidence": number, "enhancedDescription": string}

Customer's description:
"""`;

exports.analyzeJob = onCall(
  { secrets: ['GEMINI_API_KEY'] },
  async (request) => {
    if (!request.auth) {
      throw new Error('Sign in required.');
    }

    const description = typeof request.data?.description === 'string'
      ? request.data.description.trim()
      : '';
    if (description.length < 10) {
      throw new Error('description must be at least 10 characters.');
    }
    if (description.length > 2000) {
      throw new Error('description is too long (max 2000 characters).');
    }

    // Images arrive as raw base64 — job photos aren't uploaded to Storage
    // until the customer actually submits the job, so there are no
    // imageUrls yet to hand to Gemini at preview time.
    const rawImages = Array.isArray(request.data?.images) ? request.data.images : [];
    const images = rawImages
      .filter((b64) => typeof b64 === 'string' && b64.length > 0 && b64.length < 2_000_000)
      .slice(0, 3);

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({
      model: 'gemini-2.0-flash',
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: 'object',
          properties: {
            suggestedCategory: { type: 'string', enum: JOB_CATEGORIES },
            confidence: { type: 'number' },
            enhancedDescription: { type: 'string' },
          },
          required: ['suggestedCategory', 'confidence', 'enhancedDescription'],
        },
      },
    });

    const parts = [
      { text: `${ANALYZE_JOB_PROMPT}${description}"""` },
      ...images.map((data) => ({ inlineData: { mimeType: 'image/jpeg', data } })),
    ];

    let parsed;
    try {
      const result = await model.generateContent(parts);
      parsed = JSON.parse(result.response.text());
    } catch (err) {
      console.error('analyzeJob: Gemini call failed', err);
      throw new Error('AI analysis is unavailable right now. Please try again.');
    }

    // Sanitize before returning — never trust the model's output shape blindly.
    const suggestedCategory = JOB_CATEGORIES.includes(parsed.suggestedCategory)
      ? parsed.suggestedCategory
      : 'Other';
    const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
    const enhancedDescription = typeof parsed.enhancedDescription === 'string'
      ? parsed.enhancedDescription.trim().slice(0, 2000)
      : description;

    return { suggestedCategory, confidence, enhancedDescription };
  }
);
