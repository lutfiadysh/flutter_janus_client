import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:janus_client/janus_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'package:janus_client_example/conf.dart';

class TypedAudioRoomV2 extends StatefulWidget {
  @override
  _AudioRoomState createState() => _AudioRoomState();
}

class _AudioRoomState extends State<TypedAudioRoomV2> {
  JanusClient? j;
  JanusSession? session;
  JanusAudioBridgePlugin? pluginHandle;
  late WebSocketJanusTransport ws;
  late Map<String, MediaStream?> allStreams = {};
  late Map<String, RTCVideoRenderer> remoteRenderers = {};
  Map<String, AudioBridgeParticipants> participants = {};
  bool muted = false;
  bool callStarted = false;
  String myRoom="1234";

  @override
  void initState() {
    super.initState();
    initRenderers();
  }

  initRenderers() async {}

  Future<void> initPlatformState() async {
    ws = WebSocketJanusTransport(url: servermap['janus_ws']);
    j = JanusClient(withCredentials: true, isUnifiedPlan: true, apiSecret: "SecureIt", transport: ws, iceServers: [RTCIceServer(urls: "stun:stun1.l.google.com:19302", username: "", credential: "")]);
    session = await j?.createSession();
    pluginHandle = await session?.attach<JanusAudioBridgePlugin>();
    await pluginHandle?.initializeMediaDevices(mediaConstraints: {"audio": true, "video": false});
    pluginHandle?.joinRoom(myRoom, display: "Shivansh");
    pluginHandle?.remoteTrack?.listen((event) async {
      if (event.track != null && event.flowing == true && event.mid != null) {
        setState(() {
          remoteRenderers.putIfAbsent(event.mid!, () => RTCVideoRenderer());
        });
        await remoteRenderers[event.mid!]?.initialize();
        MediaStream stream = await createLocalMediaStream(event.mid!);
        setState(() {
          allStreams.putIfAbsent(event.mid!, () => stream);
        });
        allStreams[event.mid!]?.addTrack(event.track!);
        remoteRenderers[event.mid!]?.srcObject = allStreams[event.mid!];
        if (kIsWeb) {
          remoteRenderers[event.mid!]?.muted = false;
        }
      }
    });

    pluginHandle?.typedMessages?.listen((event) async {
      Object data = event.event.plugindata?.data;
      if (data is AudioBridgeJoinedEvent) {
        await pluginHandle?.configure();
         (await pluginHandle?.listParticipants(myRoom));
        data.participants?.forEach((value) {
          setState(() {
            participants.putIfAbsent(value.id.toString(), () => value);
            if (participants[value.id.toString()] != null) {
              participants[value.id.toString()] = value;
            }
          });
        });
      }
      if (data is AudioBridgeNewParticipantsEvent) {
        data.participants?.forEach((value) {
          setState(() {
            participants.putIfAbsent(value.id.toString(), () => value);
            if (participants[value.id.toString()] != null) {
              participants[value.id.toString()] = value;
            }
          });
        });
      }
      if (data is AudioBridgeConfiguredEvent) {}
      if (data is AudioBridgeLeavingEvent) {
        setState(() {
          participants.remove(data.leaving.toString());
        });
      }
      await pluginHandle?.handleRemoteJsep(event.jsep);
    });
  }

  updateTalkingId(id, talking) {
    setState(() {
      participants[id]?.talking = talking;
    });
  }

  leave() async {
    setState(() {
      participants.clear();
    });
    await pluginHandle?.hangup();
    pluginHandle?.dispose();
    session?.dispose();
  }

  cleanUpWebRTCStuff() {
    remoteRenderers.forEach((key, value) async {
      value.srcObject = null;
      await value.dispose();
    });
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    cleanUpWebRTCStuff();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
              icon: Icon(
                Icons.call,
                color: Colors.greenAccent,
              ),
              onPressed: !callStarted
                  ? () async {
                      setState(() {
                        callStarted = !callStarted;
                      });
                      await this.initRenderers();
                      await this.initPlatformState();
                    }
                  : null),
          IconButton(
              icon: Icon(
                muted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
              ),
              onPressed: callStarted
                  ? () async {
                      if (pluginHandle?.webRTCHandle?.peerConnection?.signalingState != RTCSignalingState.RTCSignalingStateClosed) {
                        setState(() {
                          muted = !muted;
                        });
                        await pluginHandle?.configure(muted: muted);
                      }
                    }
                  : null),
          IconButton(
              icon: Icon(
                Icons.call_end,
                color: Colors.red,
              ),
              onPressed: () {
                setState(() {
                  callStarted = !callStarted;
                });
                leave();
              }),
        ],
        title: const Text('janus_client'),
      ),
      body: Stack(fit: StackFit.expand, children: [
        Positioned.fill(
          top: 5,
          child: Opacity(
              opacity: 0,
              child: ListView.builder(
                  itemCount: remoteRenderers.entries.map((e) => e.value).length,
                  itemBuilder: (context, index) {
                    var renderer = remoteRenderers.entries.map((e) => e.value).toList()[index];
                    return Container(
                        color: Colors.red,
                        width: 50,
                        height: 50,
                        child: RTCVideoView(
                          renderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        ));
                  })),
        ),
        Container(
            child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          childAspectRatio: 2,
          children: participants.entries
              .map((e) => e.value)
              .map((e) => Container(
                    color: Colors.green,
                    child: Column(
                      children: [
                        Text(e.display ?? ''),
                        Icon(
                          e.muted ? Icons.mic_off : Icons.mic,
                          color: Colors.white,
                        ),
                        Icon(
                          e.talking ? Icons.volume_up_sharp : Icons.volume_mute_sharp,
                          color: Colors.white,
                        )
                      ],
                    ),
                  ))
              .toList(),
        ))
      ]),
    );
  }
}
