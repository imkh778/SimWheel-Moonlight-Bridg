import 'package:flutter/material.dart';

Future<int?> showConfirmBox(BuildContext context, {required String botton, required String title, required String s, Color color = Colors.red, int n = 2}) => showDialog<int>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(s), actions: [TextButton(onPressed: () => Navigator.pop(ctx, 0), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, 1), style: FilledButton.styleFrom(backgroundColor: color), child: Text(botton))]));
void showSnack(BuildContext context, String text, bool success) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
