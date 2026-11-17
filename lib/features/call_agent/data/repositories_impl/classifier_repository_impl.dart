import '../../domain/entities/intent.dart';
import '../../domain/repositories/classifier_repository.dart';
import '../datasources/classifier_datasource.dart';

class ClassifierRepositoryImpl implements ClassifierRepository {
  final ClassifierDatasource datasource;

  ClassifierRepositoryImpl(this.datasource);

  @override
  Future<IntentResult> classify(String text) {
    return datasource.classify(text);
  }
}
