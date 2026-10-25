import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/document.dart';

class DocumentsTile extends StatelessWidget {
  const DocumentsTile({
    super.key,
    required this.document,
    required this.uploadedBy,
    required this.onOpen,
    this.onDelete,
  });

  final Document document;
  final String uploadedBy;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  IconData get _icon {
    final ext = document.fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'dwg' || 'dxf' => Icons.architecture_outlined,
      'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onOpen,
      leading: Icon(_icon),
      title: Text(document.name),
      subtitle: Text(
        [
          document.fileName,
          uploadedBy,
          if (document.createdAt != null)
            Formatters.date(document.createdAt!.toLocal()),
        ].join(' · '),
      ),
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Delete document',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
    );
  }
}
