import 'json_utils.dart';

enum DocumentType implements JsonEnum {
  contract('contract', 'Contracts'),
  plan('plan', 'Plans'),
  permit('permit', 'Permits'),
  asBuilt('as_built', 'As-built drawings'),
  other('other', 'Other');

  const DocumentType(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static DocumentType fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `documents`.
class Document {
  const Document({
    required this.id,
    required this.projectId,
    required this.name,
    required this.docType,
    required this.fileUrl,
    required this.uploadedBy,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final String name;
  final DocumentType docType;
  final String fileUrl;
  final int uploadedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// File name from the URL, e.g. `building-permit.pdf`.
  String get fileName => Uri.parse(fileUrl).pathSegments.lastOrNull ?? fileUrl;

  factory Document.fromJson(Map<String, dynamic> json) => Document(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    name: json['name'] as String,
    docType: DocumentType.fromJson(json['doc_type']),
    fileUrl: json['file_url'] as String,
    uploadedBy: json['uploaded_by'] as int,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'name': name,
    'doc_type': docType.toJson(),
    'file_url': fileUrl,
    'uploaded_by': uploadedBy,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}
