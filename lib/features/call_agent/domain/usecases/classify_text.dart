import '../entities/intent.dart';
import '../repositories/classifier_repository.dart';

class ClassifyText {
  final ClassifierRepository repository;

  ClassifyText(this.repository);

  Future<IntentResult> call(String text) {
    return repository.classify(text);
  }
}
