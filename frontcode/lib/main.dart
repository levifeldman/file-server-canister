import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:html' as html;  
import 'package:js/js_util.dart';
import 'dart:typed_data';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/candid.dart' show c_forwards, c_backwards, Record;
import 'package:ic_tools/candid.dart' as candid;
import 'package:ic_tools_web/ic_tools_web.dart' as ic_tools_web;
import 'package:loading_animation_widget/loading_animation_widget.dart';

import './state.dart';
import './upload_folder.dart';



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
    
    ChooseServer choose_server_selection = ChooseServer.temporary;
    
    @override
    void initState() {
        super.initState();
        
        tab_controller = TabController(vsync: this, length: tabs.length);
        
        this.state.load_first_state().then((_null) { 
            setState((){
                load_first_state_future_is_complete = true;
            });
        }, onError: (e,s) {
            print(e);
            // alert dialog
            setState((){
                load_first_state_future_is_complete = true;
            });
            
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
                setState((){
                    state.loading = true;
                });
                try {
                    List<FileUpload> file_uploads = getProperty(getProperty(event, 'target'), 'files').map(FileUpload.ofAJsFile).toList(); 
                    print(file_uploads.map((fu)=>[fu.canister_upload_path(), fu.bytes.length, fu.type]).toList());
                    
                    if (choose_server_selection == ChooseServer.temporary) {
                        await state.user!.delete_user_temporary_server_files();
                        await upload_files(
                            files: file_uploads, 
                            file_server_canister: CustomState.main_canister, 
                            caller: state.user!.caller, 
                            legations: state.user!.legations
                        )    
                    }
                    
                    
                    
                    
                 
                 
                    
                } catch(e,s) {
                    print('Error syncing files: $e');
                }
                setState((){
                    state.loading = false;
                });
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
                    size: 100,
                ),
            ) : this.state.user == null ? Center(
                child: OutlinedButton(
                    child: Text('LOGIN'),
                    onPressed: () {
                        setState((){
                            state.loading = true;
                            ic_tools_web.User.login().then((ic_tools_web.User user) {
                                user.save_into_indexdb().then((_null){
                                    print('user is save in the indexdb');
                                }, onError: (e) {
                                    print('error saving user in the indexdb: $e');
                                });
                                state.user = User.of_an_ic_tools_web_user(user);
                                state.load_first_state().then((_void){
                                    setState((){
                                        state.loading = false;
                                    });  
                                }, onError: (e) {
                                    print(e);
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
                        Container(
                            width: 50,
                            child: DropdownButton(
                                items: [
                                    DropdownMenuItem(child: Text('Free Server'), value: ChooseServer.temporary),
                                    if (state.user!.user_server == null) DropdownMenuItem(child: Text('Create A Server'), value: ChooseServer.create_user_server),
                                    if (state.user!.user_server != null) DropdownMenuItem(child: Text('User Server'), value: ChooseServer.user_server),
                                ],
                                value: choose_server_selection,
                                onChanged: (ChooseServer? selection) {
                                    if (selection is ChooseServer) {
                                        setState((){
                                            choose_server_selection = selection;
                                        });
                                    }
                                },
                                elevation: 0,
                                isExpanded: true
                            ),
                        )
                        
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
    final String path;
    //final int size;
    final String content_type; // mime-type
    Future<Uint8List> bytes;
    FileUpload._({
        required this.name,
        required this.path,
        //required this.size,
        required this.content_type, // mime-type
        required this.bytes,
    });
    
    static FileUpload ofAJsFile(Object file) {        
        String name = getProperty(file, 'name');
        String webkitRelativePath = getProperty(file, 'webkitRelativePath');
        return FileUpload._(
            name: name,
            path: name == 'index.html' ? '/' : webkitRelativePath.substring(webkitRelativePath.indexOf('/')),
            //size: getProperty(file, 'size'),
            content_type: getProperty(file, 'type'),
            bytes: Future(()async{ return (await promiseToFuture(callMethod(file, 'arrayBuffer', []))).asUint8List(); })
        );
    }
    
}


Future<void> canister_upload_files(List<FileUpload> file_uploads) async {
    
    // :LOOK AT THE go.dart-put_frontcode_files-FUNCTION.

    //await Future.wait();

}



enum ChooseServer {
    temporary,
    create_user_server,
    user_server,
}

