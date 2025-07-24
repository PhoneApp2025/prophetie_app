import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  final String statusText;
  final bool isError;
  final VoidCallback onRetry;

  const StatusCard({
    Key? key,
    required this.statusText,
    this.isError = false,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isError ? Colors.red : Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isError)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blue),
              onPressed: onRetry,
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 208, 208, 208),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
