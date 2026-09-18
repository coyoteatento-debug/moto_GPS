import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImageUtils {
  const ImageUtils();

  // ── Redimensionar imagen ──────────────────────────────
  Future<Uint8List> resizeImage(Uint8List data, int targetWidth) async {
    final codec    = await ui.instantiateImageCodec(data, targetWidth: targetWidth);
    final frame    = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();  
    if (byteData == null) throw Exception('Error al redimensionar imagen');
    return byteData.buffer.asUint8List();
  }

  // ── Imagen circular con borde azul ───────────────────
  Future<Uint8List> makeCircularImage(Uint8List data, int size) async {
    // FIX: decodificar sin forzar width/height para no perder el
    // aspect ratio original de la foto.
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // FIX: recorte cuadrado centrado (crop, no stretch) — evita
    // deformar fotos rectangulares al forzarlas a un cuadrado.
    final cropSize = image.width < image.height
        ? image.width.toDouble()
        : image.height.toDouble();
    final srcRect = Rect.fromLTWH(
      (image.width - cropSize) / 2,
      (image.height - cropSize) / 2,
      cropSize,
      cropSize,
    );

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    final paint    = Paint()..isAntiAlias = true;
    final rect     = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());

    canvas.clipPath(Path()..addOval(rect));
    canvas.drawRect(rect, paint..color = Colors.white);
    canvas.drawImageRect(
      image,
      srcRect,
      rect,
      paint,
    );
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    final picture  = recorder.endRecording();
    image.dispose();
    final img      = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (byteData == null) throw Exception('Error al procesar imagen circular');
    return byteData.buffer.asUint8List();
  }

  // ── Picker desde galería ──────────────────────────────
  Future<Uint8List?> pickImageFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return null;
    return await picked.readAsBytes();
  }
}
