import 'package:flutter/material.dart';

class SearchModal extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final List<Map<String, dynamic>> results;
  final VoidCallback onClose;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<String> onChanged;
  final VoidCallback onVoiceSearch;
  final bool isListening;

  const SearchModal({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.results,
    required this.onClose,
    required this.onSelect,
    required this.onChanged,
    required this.onVoiceSearch,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.black87),
                    decoration: const InputDecoration(
                      hintText: 'Ciudad, colonia, calle...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    onChanged: onChanged,
                  ),
                ),
                // ── Botón micrófono ──────────────────────
                GestureDetector(
                  onTap: onVoiceSearch,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 36, height: 36,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: isListening
                          ? Colors.red
                          : Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isListening ? Icons.mic : Icons.mic_none,
                      color: isListening ? Colors.white : Colors.red,
                      size: 20,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else if (results.isEmpty && controller.text.length >= 3)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Sin resultados', style: TextStyle(color: Colors.grey)),
            )
          else if (results.isNotEmpty && controller.text.length >= 3)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final place = results[i];
                  final isPoi = place['type'] == 'poi';
                  final category = place['category'] as String?;
                  return ListTile(
                    leading: Icon(
                      isPoi ? Icons.storefront : Icons.location_on_outlined,
                      color: isPoi ? Colors.orange[700] : Colors.blue,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            place['name'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPoi) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Text(
                              category ?? 'Negocio',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange[800],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      place['full_name'] as String,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelect(place),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
