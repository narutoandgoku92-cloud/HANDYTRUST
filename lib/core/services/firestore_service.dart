import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> collection(String name) {
    return _firestore.collection(name);
  }

  DocumentReference<Map<String, dynamic>> document(String collectionName, String id) {
    return _firestore.collection(collectionName).doc(id);
  }
}
