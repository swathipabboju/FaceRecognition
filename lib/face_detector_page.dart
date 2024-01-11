import 'dart:typed_data';
import 'package:app/camera_view.dart';
import 'package:app/util/antispoofingmodel.dart';
import 'package:app/util/face_detector_painter.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:yuv_converter/yuv_converter.dart';
import 'package:image/image.dart' as img;

class FaceDetectorPage extends StatefulWidget {
  const FaceDetectorPage({Key? key}) : super(key: key);

  @override
  State<FaceDetectorPage> createState() => _FaceDetectorPageState();
}

class _FaceDetectorPageState extends State<FaceDetectorPage> {
  //create face detector object
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
    ),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  Uint8List imageBytes = Uint8List(0);
  static const int LAPLACE_THRESHOLD = 50;
  int? score;
  String? _note;
  double? antiSpoofingScore;

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CameraView(
            title: 'Face Detector',
            customPaint: _customPaint,
            text: _text,
            onImage: (inputImage) {
              processImage(inputImage, context);
            },
            initialDirection: CameraLensDirection.front,
          ),
          Positioned(
            top: 100,
            child: Column(
              children: [
                Text(
                  "scoreeee.. ${score} :::: ${_note}",
                  style: TextStyle(color: Colors.black),
                ),
                SizedBox(
                  height: 10,
                ),
                Text(
                  "antispoofingscore.. ${antiSpoofingScore} ",
                  style: TextStyle(color: Colors.black),
                ),
              ],
            ),
          )
        ],
      ),
      bottomSheet: Container(
        height: 100,
        child: Image.memory(imageBytes),
      ),
    );
  }

  Future<void> processImage(
      final InputImage inputImage, BuildContext contexta) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _text = "";
    });
    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isNotEmpty) {
      if (inputImage.inputImageData?.size != null &&
          inputImage.inputImageData?.imageRotation != null) {
        final painter = FaceDetectorPainter(
            faces,
            inputImage.inputImageData!.size,
            inputImage.inputImageData!.imageRotation);
        _customPaint = CustomPaint(painter: painter);
        img.Image image = _convertNV21(inputImage);
        // yuv420ToRgba8888(inputImage., inputImage.width, inputImage.height);
        img.Image rotateImg = img.copyRotate(image, angle: 270);
        img.Image faceCrop = img.copyCrop(
          rotateImg,
          x: (faces[0].boundingBox.left).toInt() /*  - 100 */,
          y: (faces[0].boundingBox.top).toInt() /* - 150 */,
          width: (faces[0].boundingBox.width).toInt() /*  + 150 */,
          height: (faces[0].boundingBox.height).toInt() /*  + 150 */,
        );
        imageBytes = img.encodeJpg(faceCrop);
        // imageBytes = YuvConverter.yuv422uyvyToRgba8888(imageBytes, 250, 250);
        setState(() {});
        score = laplacianWithImage(faceCrop);
        if (score == 0) {
          _note = "Spoofing detected";
        } else if (score! < 150) {
          _note = "Please place your face near to the camera";
        } else if (score! < 250) {
          _note = "Your camera is dusty or you are in dark light environment";
        } else {
          _note = "face detected";
          antiSpoofingScore = await FaceAntiSpoofing().loadModelImage(faceCrop);
          print(
              "spoofing score 74238462378466666666666666666 ${antiSpoofingScore}");
          setState(() {});
        }

        // _showImageDialog(contexta, faceCrop);
      } else {
        String text = 'face found ${faces.length}\n\n';
        for (final face in faces) {
          text += 'face ${face.boundingBox}\n\n';
        }
        _text = text;
        _customPaint = null;
      }
    } else {
      _customPaint = null;
      print("no faces found");
    }

    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  /* Future<Image?> convertYUV420toImage(CameraImage image) async {
    try {
      final int width = image.width;
      final int height = image.height;

      // imgLib -> Image package from https://pub.dartlang.org/packages/image
      var imgdata =
          img.Image(width: width, height: height); // Create Image buffer

      // Check if planes[0] is not null
      if (image.planes.isNotEmpty) {
        for (int x = 0; x < width; x++) {
          for (int y = 0; y < height; y++) {
            // Check if bytes is not null
            if (image.planes[0].bytes != null) {
              final pixelColor = image.planes[0].bytes![y * width + x];
              // color: 0x FF  FF  FF  FF
              //           A   B   G   R
              // Calculate pixel color
              /*   imgdata.data[y * width + x] = (0xFF << 24) |
                (pixelColor << 16) |
                (pixelColor << 8) |
                pixelColor; */
             
              imgdata.data[y * width + x] = (0xFF << 24) |
                  (pixelColor << 16) |
                  (pixelColor << 8) |
                  pixelColor;
            }
          }
        }
      }

      img.PngEncoder pngEncoder = new img.PngEncoder(level: 0, filter: 0);
      List<int> png = pngEncoder.encode(imgdata);
      return Image.memory(Uint8List.fromList(png));
    } catch (e) {
      print(">>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }
 */
  img.Image _convertNV211(CameraImage image) {
    final width = image.width.toInt();
    final height = image.height.toInt();

    Uint8List yuv420sp = image.planes[0].bytes;

    final outImg = img.Image(width: width, height: height);
    final int frameSize = width * height;

    for (int j = 0, yp = 0; j < height; j++) {
      int uvp = frameSize + (j >> 1) * width, u = 0, v = 0;
      for (int i = 0; i < width; i++, yp++) {
        int y = (0xff & yuv420sp[yp]) - 16;
        if (y < 0) y = 0;
        if ((i & 1) == 0) {
          v = (0xff & yuv420sp[uvp++]) - 128;
          u = (0xff & yuv420sp[uvp++]) - 128;
        }
        int y1192 = 1192 * y;
        int r = (y1192 + 1634 * v);
        int g = (y1192 - 833 * v - 400 * u);
        int b = (y1192 + 2066 * u);

        if (r < 0)
          r = 0;
        else if (r > 262143) r = 262143;
        if (g < 0)
          g = 0;
        else if (g > 262143) g = 262143;
        if (b < 0)
          b = 0;
        else if (b > 262143) b = 262143;

        // I don't know how these r, g, b values are defined, I'm just copying what you had bellow and
        // getting their 8-bit values.
        /*  outImg.setPixelRgba(i, j, ((r << 6) & 0xff0000) >> 16,
            ((g >> 2) & 0xff00) >> 8, (b >> 10) & 0xff); */
        outImg.setPixelRgba(
          i,
          j,
          ((r << 6) & 0xff0000) >> 16,
          ((g >> 2) & 0xff00) >> 8,
          (b >> 10) & 0xff,
          255,
        );
      }
    }
    return outImg;
  }

  img.Image _convertNV21(InputImage image) {
    int? width = image.inputImageData?.size.width.toInt();
    int? height = image.inputImageData?.size.height.toInt();

    Uint8List? yuv420sp = image.bytes;

    final outImg = img.Image(width: width ?? 0, height: height ?? 0);
    final int frameSize = width! * height!;

    for (int j = 0, yp = 0; j < height; j++) {
      int uvp = frameSize + (j >> 1) * width, u = 0, v = 0;
      for (int i = 0; i < width; i++, yp++) {
        int y = (0xff & yuv420sp![yp]) - 16;
        if (y < 0) y = 0;
        if ((i & 1) == 0) {
          v = (0xff & yuv420sp[uvp++]) - 128;
          u = (0xff & yuv420sp[uvp++]) - 128;
        }
        int y1192 = 1192 * y;
        int r = (y1192 + 1634 * v);
        int g = (y1192 - 833 * v - 400 * u);
        int b = (y1192 + 2066 * u);

        if (r < 0)
          r = 0;
        else if (r > 262143) r = 262143;
        if (g < 0)
          g = 0;
        else if (g > 262143) g = 262143;
        if (b < 0)
          b = 0;
        else if (b > 262143) b = 262143;

        // I don't know how these r, g, b values are defined, I'm just copying what you had bellow and
        // getting their 8-bit values.
        /*  outImg.setPixelRgba(i, j, ((r << 6) & 0xff0000) >> 16,
            ((g >> 2) & 0xff00) >> 8, (b >> 10) & 0xff); */
        outImg.setPixelRgba(
          i,
          j,
          ((r << 6) & 0xff0000) >> 16,
          ((g >> 2) & 0xff00) >> 8,
          (b >> 10) & 0xff,
          255,
        );
        /*  outImg.setPixelRgba(
          i,
          j,
          255,
          255,
          255,
          255,
        ); */
      }
    }
    return outImg;
  }
  Uint8List yuv420ToRgba8888(List<Uint8List> planes, int width, int height) {
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];

  final Uint8List rgbaBytes = Uint8List(width * height * 4);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int yIndex = y * width + x;
      final int uvIndex = (y ~/ 2) * (width ~/ 2) + (x ~/ 2);

      final int yValue = yPlane[yIndex] & 0xFF;
      final int uValue = uPlane[uvIndex] & 0xFF;
      final int vValue = vPlane[uvIndex] & 0xFF;

      final int r = (yValue + 1.13983 * (vValue - 128)).round().clamp(0, 255);
      final int g =
          (yValue - 0.39465 * (uValue - 128) - 0.58060 * (vValue - 128))
              .round()
              .clamp(0, 255);
      final int b = (yValue + 2.03211 * (uValue - 128)).round().clamp(0, 255);

      final int rgbaIndex = yIndex * 4;
      rgbaBytes[rgbaIndex] = r.toUnsigned(8);
      rgbaBytes[rgbaIndex + 1] = g.toUnsigned(8);
      rgbaBytes[rgbaIndex + 2] = b.toUnsigned(8);
      rgbaBytes[rgbaIndex + 3] = 255; // Alpha value
    }
  }

  return rgbaBytes;
}


  void _showImageDialog(BuildContext context, img.Image image) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Image Dialog'),
          content: Image.memory(
            img.encodeJpg(image), // Replace with your image path
            width: 200.0,
            height: 200.0,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  int laplacianWithImage(img.Image image) {
    final INPUT_IMAGE_SIZE = 256;

    // Convert the image data to a grayscale image
    List<List<int>> img = convertToGreyImgWithImage(image, INPUT_IMAGE_SIZE);

    int size = 3; // Size of the laplace filter
    int height = img.length;
    int width = img[0].length;

    // Laplace matrix
    List<List<int>> laplace = [
      [0, 1, 0],
      [1, -4, 1],
      [0, 1, 0],
    ];

    int score = 0;
    for (int x = 0; x < height - size + 1; x++) {
      for (int y = 0; y < width - size + 1; y++) {
        int result = 0;
        // Perform convolution operation on size*size area
        for (int i = 0; i < size; i++) {
          for (int j = 0; j < size; j++) {
            result += (img[x + i][y + j] & 0xFF) * laplace[i][j];
          }
        }
        if (result > LAPLACE_THRESHOLD) {
          score++;
        }
      }
    }
    return score;
  }

  List<List<int>> convertToGreyImgWithImage(img.Image image, int imageSize) {
    // Assuming the image contains RGB values
    List<List<int>> imggg =
        List.generate(imageSize, (index) => List<int>.filled(imageSize, 0));

    try {
      for (int i = 0; i < imageSize; i++) {
        for (int j = 0; j < imageSize; j++) {
          img.Pixel pixel = image.getPixel(i, j);
          int red = pixel.r.toInt();
          int green = pixel.g.toInt();
          int blue = pixel.b.toInt();

          imggg[i][j] = calculateLuminance(red, green, blue);
        }
      }
    } catch (e) {
      print(e);
    }

    return imggg;
  }

  int calculateLuminance(int red, int green, int blue) {
    return ((0.299 * red) + (0.587 * green) + (0.114 * blue)).round();
  }
}
