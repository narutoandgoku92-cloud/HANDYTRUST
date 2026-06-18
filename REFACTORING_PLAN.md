# HandyTrust Refactoring Master Plan

## Current Status Audit

### What Exists ✓
- [x] Firebase Auth (currently phone OTP + anonymous)
- [x] Firestore integration
- [x] Basic job system
- [x] Chat system
- [x] Artisan/customer distinction
- [x] Review system
- [x] Dispute system
- [x] Payment/escrow system (dummy)
- [x] Navigation structure
- [x] Core models (User, Job, Artisan, etc.)

### Critical Issues to Fix 🚨
1. Auth system needs refactor (email/password + role-based)
2. Job lifecycle not strictly enforced
3. Chat not properly job-linked
4. Firestore structure may need alignment
5. UI inconsistent (needs minimalist fintech design)
6. Security rules need strengthening
7. No component standardization
8. AI ranking not implemented

---

## Refactoring Phases (SAFE, INCREMENTAL)

### Phase 1: Auth System Refactor (CRITICAL - WEEK 1)
**Goal:** Establish role-based routing foundation

- [ ] Audit current auth flow
- [ ] Add email/password auth support
- [ ] Implement role field validation
- [ ] Create role-based routing (customer/artisan/admin)
- [ ] Add user profile migration
- [ ] Test: Auth flow intact, roles enforced
- [ ] Verify: No breakage in existing phone auth

### Phase 2: Firestore Migration (WEEK 1-2)
**Goal:** Align data structure with job-centric design

- [ ] Audit current Firestore structure
- [ ] Create migration adapters (backward compat)
- [ ] Map existing data to new structure
- [ ] Ensure jobId links for: chat, quotes, disputes, reviews
- [ ] Test: All reads/writes valid
- [ ] Verify: No data loss

### Phase 3: Job Lifecycle Enforcement (WEEK 2)
**Goal:** Strict state machine for job workflow

- [ ] Implement state machine validator
- [ ] Refactor existing job logic to follow: posted → requested → accepted → scheduled → in_progress → completed_attempt → completed/disputed/cancelled
- [ ] Add transition validation
- [ ] Test: Invalid transitions blocked
- [ ] Verify: Existing jobs still functional

### Phase 4: Chat Refactoring (WEEK 2-3)
**Goal:** Job-linked chat only

- [ ] Audit current chat system
- [ ] Add jobId requirement for chat access
- [ ] Implement access control (job participants only)
- [ ] Refactor UI to show job context
- [ ] Test: Chat restrictions enforced
- [ ] Verify: No broken conversations

### Phase 5: Dispute System Completion (WEEK 3)
**Goal:** Proper dispute workflow

- [ ] Verify dispute creation after completed_attempt
- [ ] Add job locking when dispute created
- [ ] Implement admin resolution workflow
- [ ] Add status transitions: completed/cancelled
- [ ] Test: Dispute flow works end-to-end
- [ ] Verify: Job locked during dispute

### Phase 6: Escrow Implementation (WEEK 3)
**Goal:** Dummy escrow system integration

- [ ] Audit current escrow logic
- [ ] Add escrowStatus field: held | released | pending
- [ ] Implement release on job completion
- [ ] Test: Escrow state transitions
- [ ] Verify: State consistent with job lifecycle

### Phase 7: Artisan System Upgrades (WEEK 4)
**Goal:** Production-ready artisan features

- [ ] Implement verification requirement
- [ ] Add availability calendar system
- [ ] Implement trustScore + rating system
- [ ] Add job history tracking
- [ ] Test: Artisans properly verified
- [ ] Verify: Ranking logic works

### Phase 8: Review System Finalization (WEEK 4)
**Goal:** Bidirectional, immutable reviews

- [ ] Ensure reviews only after completed jobs
- [ ] Implement bidirectional review capability
- [ ] Add immutability after creation
- [ ] Test: Reviews create/retrieve properly
- [ ] Verify: Ratings aggregate correctly

### Phase 9: AI Ranking System (WEEK 4-5)
**Goal:** Lightweight AI-powered artisan discovery

- [ ] Implement trustScore calculation
- [ ] Add rating-based ranking
- [ ] Implement job-history-based ranking
- [ ] Create artisan recommendation feed
- [ ] Test: Ranking algorithm works
- [ ] Verify: Feed ordering correct

### Phase 10: UI Refactor (WEEK 5-6)
**Goal:** Minimalist fintech design

- [ ] Create component library (Card, Button, StatusChip, etc.)
- [ ] Refactor authentication screens
- [ ] Refactor customer app UI
- [ ] Refactor artisan app UI
- [ ] Refactor admin panel UI
- [ ] Test: All screens render correctly
- [ ] Verify: No visual regressions

### Phase 11: Firebase Security (WEEK 6)
**Goal:** Production-grade Firestore rules

- [ ] Enforce user profile access rules
- [ ] Enforce job participant-only access
- [ ] Enforce job-restricted chat access
- [ ] Enforce immutable disputes
- [ ] Hide unverified artisans
- [ ] Test: Unauthorized access blocked
- [ ] Verify: All valid access allowed

### Phase 12: Final Integration & Testing (WEEK 6-7)
**Goal:** Production-ready system

- [ ] End-to-end flow testing
- [ ] Performance testing
- [ ] Security testing
- [ ] Load testing (dummy data)
- [ ] Documentation
- [ ] Deployment readiness

---

## Safety Checkpoints (MANDATORY AFTER EACH PHASE)

After every phase, you MUST verify:

```
✓ App compiles without errors
✓ No new runtime crashes
✓ Auth flow still works (all methods)
✓ Navigation stack correct
✓ Firestore reads/writes valid
✓ Job lifecycle preserved
✓ No data loss
✓ Role-based access enforced
```

If ANY checkpoint fails:
- **STOP immediately**
- **Revert changes**
- **Fix root cause**
- **Re-verify before continuing**

---

## File Structure (Target End State)

```
lib/
├── core/
│   ├── auth/
│   │   ├── auth_service.dart (email + phone)
│   │   ├── role_validator.dart
│   │   └── auth_providers.dart
│   ├── services/
│   │   ├── firestore_service.dart
│   │   ├── chat_service.dart (job-linked)
│   │   ├── job_service.dart (state machine)
│   │   ├── artisan_service.dart
│   │   ├── dispute_service.dart
│   │   ├── escrow_service.dart
│   │   ├── review_service.dart
│   │   └── ai_ranking_service.dart
│   └── models/ (validated, job-linked)
│
├── features/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   ├── signup_screen.dart
│   │   └── role_setup_screen.dart
│   ├── customer/
│   │   ├── screens/
│   │   └── widgets/
│   ├── artisan/
│   │   ├── screens/
│   │   └── widgets/
│   ├── admin/
│   │   ├── screens/
│   │   └── widgets/
│   ├── job/
│   │   ├── job_detail_screen.dart
│   │   ├── job_lifecycle_manager.dart
│   │   └── widgets/
│   ├── chat/
│   │   ├── job_chat_screen.dart
│   │   └── widgets/
│   ├── dispute/
│   │   ├── dispute_screen.dart
│   │   └── widgets/
│   └── review/
│       ├── review_screen.dart
│       └── widgets/
│
├── ui/
│   ├── components/
│   │   ├── buttons.dart
│   │   ├── cards.dart
│   │   ├── chips.dart
│   │   ├── rating_stars.dart
│   │   └── etc.
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── app_colors.dart
│   └── spacing/
│
├── providers/ (Riverpod)
│   ├── auth_provider.dart
│   ├── job_provider.dart
│   ├── chat_provider.dart
│   ├── artisan_provider.dart
│   └── etc.
│
├── routes/
│   ├── app_router.dart (role-based)
│   └── route_paths.dart
│
├── firebase_options.dart
├── main.dart
└── app.dart
```

---

## Rollback Strategy

If a phase breaks something:

1. **Identify** what broke
2. **Document** the exact issue
3. **Revert** that phase only
4. **Fix** the root cause in isolation
5. **Re-test** before moving forward
6. **Never** skip a safety checkpoint

---

## Success Criteria (Final State)

✅ **Auth**
- Email/password + phone auth working
- Roles enforced (customer/artisan/admin)
- Role-based routing active
- User profiles required

✅ **Data**
- All job-linked entities (chat, quotes, disputes, reviews)
- Firestore structure aligned
- No orphaned data
- Role-based access enforced

✅ **Job Lifecycle**
- State machine enforced
- Invalid transitions blocked
- All transitions valid
- Job lifecycle integrity

✅ **Features**
- Chat job-restricted
- Disputes immutable
- Escrow state tracking
- Artisan verification required
- Reviews bidirectional
- AI ranking active

✅ **UI**
- Minimalist fintech design
- Component standardization
- No visual regressions
- Consistent spacing (8pt)

✅ **Security**
- Users access own data only
- Jobs restricted to participants
- Chats job-restricted
- Artisans verified before display
- All rules enforced

---

## Start Point

**Phase 1 begins with:** Auth system audit
**Next step:** Read current auth implementation, plan refactor path

**SAFETY RULE:** Do not proceed until current state is fully understood.
