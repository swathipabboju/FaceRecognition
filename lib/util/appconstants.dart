import 'dart:io';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// ignore: depend_on_referenced_packages

class AppConstants {
  AppConstants._();
  static InputImage? inputImage;

  static List<Face>? faces;
  static String? filpath;

  static Image? faceCrop;
  static File? cropSveFile;
  static Rect? faceRect;
}
