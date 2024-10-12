import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAe1x3pal_VTKm1GlDMMndAHto2FemmgRI",
      authDomain: "vc--projet.firebaseapp.com",
      databaseURL: "https://vc--projet-default-rtdb.firebaseio.com",
      projectId: "vc--projet",
      storageBucket: "vc--projet.appspot.com",
      messagingSenderId: "407917098561",
      appId: "1:407917098561:web:d894099f0a61bd517db8c0",
      measurementId: "G-1V6RFCP5PE",
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Chat & Video Call App',
      home: AuthScreen(),
    );
  }
}

// Authentication Screen
class AuthScreen extends StatelessWidget {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  AuthScreen({super.key});

  void login() async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      print("User signed in: ${userCredential.user?.email}");
      Get.to(ChatScreen());
    } catch (e) {
      print("Error signing in: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email')),
            TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password')),
            ElevatedButton(onPressed: login, child: const Text('Login')),
          ],
        ),
      ),
    );
  }
}

// Chat Screen
class ChatScreen extends StatelessWidget {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController messageController = TextEditingController();

  ChatScreen({super.key});

  void sendMessage() async {
    if (messageController.text.isNotEmpty) {
      String messageText = messageController.text;

      // Check if the message is a URL
      if (Uri.tryParse(messageText)?.hasScheme ?? false) {
        // Open the URL
        if (await canLaunch(messageText)) {
          await launch(messageText);
        } else {
          print("Could not launch $messageText");
        }
      } else {
        // Send the message as text
        _firestore.collection('chats').add({
          'message': messageText,
          'timestamp': Timestamp.now(),
        });
      }

      messageController.clear();
    }
  }

  void createVideoCall() async {
    // Generate a unique call ID (you can customize this)
    String callId = DateTime.now().millisecondsSinceEpoch.toString();
    String callLink =
        'https://vc--projet.firebaseapp.com/video_call?id=$callId';

    // Save call details to Firestore
    await _firestore.collection('calls').doc(callId).set({
      'link': callLink,
      'timestamp': Timestamp.now(),
    });

    // Share the link
    print('Video call link: $callLink');
    if (await canLaunch(callLink)) {
      await launch(callLink);
    } else {
      print("Could not launch $callLink");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _firestore
                  .collection('chats')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                return ListView(
                  children: snapshot.data!.docs.map((doc) {
                    return ListTile(title: Text(doc['message']));
                  }).toList(),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration:
                        const InputDecoration(hintText: 'Enter a message'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: createVideoCall,
        child: const Icon(Icons.video_call), // Create video call link on press
      ),
    );
  }
}

// Video Call Screen using WebRTC
class VideoCallScreen extends StatefulWidget {
  final String callId;

  const VideoCallScreen({super.key, required this.callId});

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final webrtc.RTCVideoRenderer _localRenderer = webrtc.RTCVideoRenderer();
  final webrtc.RTCVideoRenderer _remoteRenderer = webrtc.RTCVideoRenderer();
  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? _localStream;
  CollectionReference signalingCollection =
      FirebaseFirestore.instance.collection('calls');
  bool remoteDescriptionSet = false;

  @override
  void initState() {
    super.initState();
    initRenderers();
    startCall();
  }

  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> startCall() async {
    Map<String, dynamic> config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await webrtc.createPeerConnection(config);

    _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });

    _localRenderer.srcObject = _localStream;

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
      signalingCollection.doc(widget.callId).update({
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _peerConnection!.onTrack = (webrtc.RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };

    webrtc.RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    signalingCollection.doc(widget.callId).set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
    });

    signalingCollection.doc(widget.callId).snapshots().listen((snapshot) async {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        if (data.containsKey('answer') && !remoteDescriptionSet) {
          var answer = data['answer'];
          await _peerConnection!.setRemoteDescription(
            webrtc.RTCSessionDescription(answer['sdp'], answer['type']),
          );
          remoteDescriptionSet = true;
        } else if (data.containsKey('candidate') && remoteDescriptionSet) {
          var candidate = data['candidate'];
          await _peerConnection!.addCandidate(webrtc.RTCIceCandidate(
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Call')),
      body: Column(
        children: [
          Expanded(child: webrtc.RTCVideoView(_localRenderer)),
          Expanded(child: webrtc.RTCVideoView(_remoteRenderer)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    super.dispose();
  }
}
