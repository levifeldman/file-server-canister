import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:html' as html;  
import 'package:js/js_util.dart';
import 'dart:typed_data';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/candid.dart' show c_forwards, c_backwards, Record;
import 'package:ic_tools/candid.dart' as candid;
import 'package:ic_tools_web/ic_tools_web.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import './state.dart';




//final Canister server = Canister(Principal(''));


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Server Canister',
      theme: ThemeData(
        primarySwatch: Colors.red,
        appBarTheme: AppBarTheme(
            //color: blue, 
            backgroundColor: Colors.red, 
            //foregroundColor: double?, 
            elevation: 0.0,  
            shadowColor: null,  
        )
      ),
      home: const MyHomePage(),
    );
  }
}

final List<String> tabs = [
    'SYNC FILES',
    'BROWSE FILES'
];


class MyHomePage extends StatefulWidget {
    const MyHomePage({super.key});

    @override
    State<MyHomePage> createState() => _MyHomePageState();  
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {
    late html.Element input_directory;  
    //final String temp_canister_server_dir = DateTime.now().millisecondsSinceEpoch.toString;
    CustomState state = CustomState();
    bool load_first_state_future_is_complete = false;
    
    late TabController tab_controller;
    
    @override
    void initState() {
        super.initState();
        
        tab_controller = TabController(vsync: this, length: tabs.length);
        
        this.state.load_first_state().then((_null) { 
            this.setState((){
                load_first_state_future_is_complete = true;
            });
        }, onError: (e,s) {
            print(e);
        });
        
        input_directory = html.Element.html(
            '<input type="file" id="directorypicker" name="fileList" webkitdirectory />',
            validator: html.NodeValidatorBuilder()
                ..allowHtml5(uriPolicy: ItemUrlPolicy())
                ..allowNavigation(ItemUrlPolicy())
                ..allowImages(ItemUrlPolicy())
                ..allowElement('input', attributes: ['webkitdirectory'])
        );
        
        input_directory.addEventListener(
            "change",
            (html.Event event) async {
                List<FileUpload> file_uploads = await Future.wait(getProperty(getProperty(event, 'target'), 'files').map<Future<FileUpload>>(FileUpload.ofAJsFile)); 
                print(file_uploads.map((fu)=>[fu.canister_upload_path(), fu.bytes.length]).toList());
                
                
                /*
                for (Object file in getProperty(getProperty(event, 'target'), 'files')) {
                    String webkitRelativePath = getProperty(file, 'webkitRelativePath');
                    print(webkitRelativePath.substring(webkitRelativePath.indexOf('/')));
                }
                */
            },
            false
        );
        /*
        ui.platformViewRegistry.registerViewFactory(
            'input_directory_view_type',
            (int viewId) => input_directory
        );
        */
    }
  

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: Text('File Server Canister'),
                bottom: TabBar(
                    controller: tab_controller,
                    tabs: tabs.map((s)=>Tab(text: s)).toList()
                ),
            ),
            body: this.load_first_state_future_is_complete == false || this.state.loading ? Center(
                child: LoadingAnimationWidget.threeArchedCircle( // fade this in and out
                    color: Colors.black,
                    size: 200,
                ),
            ) : this.state.user == null ? Center(
                child: OutlinedButton(
                    child: Text('LOGIN'),
                    onPressed: () {
                        setState((){
                            state.loading = true;
                            User.login().then((User user) {
                                setState((){
                                    state.user = user;
                                    state.loading = false;
                                });
                            }, onError: (authorize_client_error) {
                                print(authorize_client_error);   
                            });
                        });
                    }
                )
            ) : /*this.state.user != null ? */ Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                        Text('welcome user: ${state.user!.principal.text}'),
                        /*
                        Container(
                            width: 70,
                            height: 50,
                            child: HtmlElementView(
                                viewType: 'input_directory_view_type',
                            ),
                        ),
                        */
                        ElevatedButton(
                            child: Text('Upload Folder'),
                            onPressed: () {
                                input_directory.click();
                            }
                        )      
                    ],
                ),
            ),     
        ); 
    }
}


class ItemUrlPolicy implements html.UriPolicy {
  RegExp regex = RegExp(r'(?:http://|https://)?.*');

  bool allowsUri(String uri) {
    return regex.hasMatch(uri);
  }
}



class FileUpload {
    final String name;
    final String webkitRelativePath;
    final int size;
    final String type; // mime-type
    final Uint8List bytes;
    FileUpload._({
        required this.name,
        required this.webkitRelativePath,
        required this.size,
        required this.type, // mime-type
        required this.bytes,
    });
    
    static Future<FileUpload> ofAJsFile(Object file) async {        
        return FileUpload._(
            name: getProperty(file, 'name'),
            webkitRelativePath: getProperty(file, 'webkitRelativePath'),
            size: getProperty(file, 'size'),
            type: getProperty(file, 'type'),
            bytes: (await promiseToFuture(callMethod(file, 'arrayBuffer', []))).asUint8List()
        );
    }
    
    String canister_upload_path() {
        if (this.name == 'index.html') {
            return '/';
        } else {
            return this.webkitRelativePath.substring(this.webkitRelativePath.indexOf('/'));
        }
    }
}


Future<void> canister_upload_files(List<FileUpload> file_uploads) async {
    
    // :LOOK AT THE go.dart-put_frontcode_files-FUNCTION.

    //await Future.wait();

}
