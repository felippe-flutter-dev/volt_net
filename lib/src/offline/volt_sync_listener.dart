import 'dart:async';
import 'package:flutter/material.dart';
import 'sync_queue_manager.dart';

/// A helper widget that automatically listens to VoltNet sync events
/// and triggers a callback (like refreshing a list) without boilerplate.
class VoltSyncListener extends StatefulWidget {
  final Widget child;
  final VoidCallback onSync;
  final String? endpoint;

  const VoltSyncListener({
    super.key,
    required this.child,
    required this.onSync,
    this.endpoint,
  });

  @override
  State<VoltSyncListener> createState() => _VoltSyncListenerState();
}

class _VoltSyncListenerState extends State<VoltSyncListener> {
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = SyncQueueManager().onQueueFinished.listen((_) {
      if (mounted) {
        widget.onSync();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
