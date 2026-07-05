import 'package:flutter/material.dart';

class Buttoncard extends StatelessWidget {
  const Buttoncard({Key? key, required this.name, required this.icon})
    : super(key: key);

  final String name;
  final IconData icon;

  String _getInitials() {
    if (name.isEmpty) return "?";
    return name.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 23,
        backgroundColor: const Color.fromARGB(255, 56, 3, 155),
        child: icon != null
            ? Icon(icon, size: 20, color: Colors.white)
            : Text(
                _getInitials(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
