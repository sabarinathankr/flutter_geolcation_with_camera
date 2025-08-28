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
      title: 'Camera & Map Demo',
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

  bool _isRecording = false;
  XFile? _videoFile;

  double? currentLatitude;
  double? currentLongitude;
  LatLng _selectedLocation = LatLng(11.032490, 77.005318);

  final Location location = Location();
  String currentLatLon = "";

  Duration _recordingDuration = Duration.zero;
  DateTime? _recordingStartTime;
  Timer? _timer;

  List<Map<String, dynamic>> pinnedLocationsData = [];
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: true,
    );
    _initializeControllerFuture = _controller.initialize();

    location.onLocationChanged.listen((LocationData currentLocation) {
      if (currentLocation.latitude != null &&
          currentLocation.longitude != null) {
        setState(() {
          currentLatitude = currentLocation.latitude;
          currentLongitude = currentLocation.longitude;
          currentLatLon =
              'Lat: ${currentLatitude!.toStringAsFixed(6)}, Lon: ${currentLongitude!.toStringAsFixed(6)}';
        });
      }
    });

    getLocation();
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
        _recordingDuration = Duration.zero;
      });
      _timer?.cancel();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording stopped!')),
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

  void getLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera preview
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return CameraPreview(_controller);
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),

          // Recording duration at top center
          if (_isRecording)
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Red blinking dot
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_recordingDuration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${_recordingDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Record button at bottom center
          Positioned(
            bottom: 200,
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
                      color: _isRecording ? Colors.red : Colors.green,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        )
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.videocam,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Draggable bottom sheet for Map
          DraggableScrollableSheet(
            initialChildSize: 0.2,
            minChildSize: 0.2,
            maxChildSize: 0.8,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, -3))
                  ],
                ),
                child: SingleChildScrollView(
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child:
                      Column(
                        children: [
                          const Icon(
                            Icons.menu,
                            size: 20,
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.8,
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    center: _selectedLocation,
                                    zoom: 14.0,
                                    minZoom: 5.0,
                                    maxZoom: 18.0,
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
                                // Pin Location button (top-right)
                                Positioned(
                                  top: 16,
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
                                // My Location button (top-left)
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
                      )

                    )),
              );
            },
          ),
        ],
      ),
    );
  }
}
