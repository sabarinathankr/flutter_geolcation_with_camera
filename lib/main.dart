import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Welcome',
      home: HomeScreen(camera: camera),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final CameraDescription camera;

  const HomeScreen({super.key, required this.camera});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  double? currentLatitude;
  double? currentLongitude;

  bool _isRecording = false;
  XFile? _videoFile;

  LatLng _selectedLocation = LatLng(11.032490, 77.005318);
  double _cameraFraction = 0.5;

  final Location location = Location();
  String currentLatLon = "";

  // Timer variables
  Duration _recordingDuration = Duration.zero;
  DateTime? _recordingStartTime;
  Timer? _timer;

  // JSON array to store pinned location data
  List<Map<String, dynamic>> pinnedLocationsData = [];

  final MapController _mapController = MapController(); // <-- Add this

  void navigateToMyLocation() {
    if (currentLatitude != null && currentLongitude != null) {
      _mapController.move(LatLng(currentLatitude!, currentLongitude!), 14.0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location not available')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    _initializeControllerFuture = _controller.initialize();

    // Listen to location changes
    location.onLocationChanged.listen((LocationData currentLocation) {
      if (currentLocation.latitude != null &&
          currentLocation.longitude != null) {
        setState(() {
          currentLongitude = currentLocation.longitude;
          currentLatitude = currentLocation.latitude;
          currentLatLon =
              'Lat: ${currentLatitude!.toStringAsFixed(6)}, Lon: ${currentLongitude!.toStringAsFixed(6)}';
        });
      }
    });

    getLocation(); // Get initial location
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void toggleRecording() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    if (!_controller.value.isRecordingVideo) {
      await _controller.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
        _recordingStartTime = DateTime.now();
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        });
      });
    }
  }

  Future<void> stopRecording() async {
    if (_controller.value.isRecordingVideo) {
      final videoFile = await _controller.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _videoFile = videoFile;
        _recordingDuration = Duration.zero; // Reset timer after stop
      });

      _timer?.cancel();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording stopped!'),
        ),
      );
    }
  }

  void pinLocation() {
    if (_recordingDuration.inSeconds == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please start recording first!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (currentLatitude != null && currentLongitude != null) {
      pinnedLocationsData.add({
        "duration_seconds": _recordingDuration.inSeconds,
        "latitude": currentLatitude,
        "longitude": currentLongitude,
        "timestamp": DateTime.now().toIso8601String(),
      });

      print("Pinned JSON Data: ${jsonEncode(pinnedLocationsData)}");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pinned Location at: $currentLatLon')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
    }
  }

  /* void navigateToMyLocation() {
    if (currentLatitude != null && currentLongitude != null) {
      setState(() {
        _selectedLocation = LatLng(currentLatitude!, currentLongitude!);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location not available')),
      );
    }
  }*/

  void getLocation() async {
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) return;
    }

    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) return;
    }

    final loc = await location.getLocation();
    if (loc.latitude != null && loc.longitude != null) {
      setState(() {
        _selectedLocation = LatLng(loc.latitude!, loc.longitude!);
        currentLatLon =
            'Lat: ${loc.latitude!.toStringAsFixed(6)}, Lon: ${loc.longitude!.toStringAsFixed(6)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Camera & Map Demo")),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalHeight = constraints.maxHeight;
                  final cameraHeight = totalHeight * _cameraFraction;
                  final mapHeight = totalHeight * (1 - _cameraFraction) - 16;

                  return Column(
                    children: [
                      // Camera preview with timer and toggle button
                      SizedBox(
                        height: cameraHeight,
                        child: Stack(
                          children: [
                            FutureBuilder<void>(
                              future: _initializeControllerFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.done) {
                                  return CameraPreview(_controller);
                                } else {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                              },
                            ),
                            if (_isRecording)
                              Positioned(
                                top: 16,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_recordingDuration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${_recordingDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: toggleRecording,
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isRecording
                                            ? Colors.red
                                            : Colors.green,
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 6,
                                            offset: Offset(0, 3),
                                          )
                                        ],
                                      ),
                                      child: Icon(
                                        _isRecording
                                            ? Icons.stop
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Draggable divider
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragUpdate: (details) {
                          setState(() {
                            _cameraFraction += details.delta.dy / totalHeight;
                            if (_cameraFraction < 0.2) _cameraFraction = 0.2;
                            if (_cameraFraction > 0.8) _cameraFraction = 0.8;
                          });
                        },
                        child: Container(
                          color: Colors.grey[300],
                          height: 16,
                          child: Center(
                            child: Container(
                              width: 80,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.grey[600],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Map view with buttons
                      SizedBox(
                        height: mapHeight,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                center: _selectedLocation,
                                zoom: 14.0,
                                minZoom: 5.0,
                                maxZoom: 18.0,
                                interactiveFlags: InteractiveFlag.all,
                                onTap: (tapPosition, latLng) {
                                  setState(() {
                                    _selectedLocation = latLng;
                                  });
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                                  subdomains: ['a', 'b', 'c'],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _selectedLocation,
                                      width: 80,
                                      height: 80,
                                      builder: (ctx) => const Icon(
                                        Icons.location_on,
                                        color: Colors.red,
                                        size: 40,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Pin Location button bottom-right
                            Positioned(
                              bottom: 16,
                              right: 16,
                              child: ElevatedButton.icon(
                                onPressed: pinLocation,
                                icon: const Icon(Icons.push_pin),
                                label: const Text("Pin Location",
                                    style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            // My Location button top-left
                            Positioned(
                              top: 16,
                              left: 16,
                              child: FloatingActionButton(
                                mini: true,
                                onPressed: navigateToMyLocation,
                                child: const Icon(Icons.my_location),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
