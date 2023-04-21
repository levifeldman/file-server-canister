import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:html' as html;  
import 'package:js/js_util.dart';
import 'dart:typed_data';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/common.dart';
import 'package:ic_tools/candid.dart' show c_forwards, c_backwards, Record;
import 'package:ic_tools/candid.dart' as candid;
import 'package:ic_tools_web/ic_tools_web.dart' as ic_tools_web;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:url_launcher/link.dart';

import './state.dart';
import './upload_folder.dart';
import './files_and_directories.dart';





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

class _MyHomePageState extends State<MyHomePage> {//  with SingleTickerProviderStateMixin {
    late html.Element input_directory;  
    //final String temp_canister_server_dir = DateTime.now().millisecondsSinceEpoch.toString;
    CustomState state = CustomState();
    bool load_first_state_future_is_complete = false;
    
    //late TabController tab_controller;
    
    UserServer? user_server_selection;
    
    @override
    void initState() {
        super.initState();
        
        //tab_controller = TabController(vsync: this, length: tabs.length);
        
        this.state.load_first_state().then((_null) { 
            setState((){
                load_first_state_future_is_complete = true;
                user_server_selection = state.user != null ? state.user!.user_servers.length >= 1 ? state.user!.user_servers.first : null : null;
            });
        }, onError: (e,s) {
            print(e);
            // alert dialog
            setState((){
                load_first_state_future_is_complete = true;
                user_server_selection = state.user != null ? state.user!.user_servers.length >= 1 ? state.user!.user_servers.first : null : null;
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
                
                    //List<FileUpload> file_uploads = await Future.wait(getProperty(getProperty(event, 'target'), 'files').map<Future<FileUpload>>(FileUpload.ofAJsFile));
                    
                    List<FileUpload> file_uploads = [];
                    for (Object file in getProperty(getProperty(event, 'target'), 'files')) {
                        file_uploads.add(
                            await file_upload_of_a_js_file(file)
                        );
                        //String webkitRelativePath = getProperty(file, 'webkitRelativePath');
                        //print(webkitRelativePath.substring(webkitRelativePath.indexOf('/')));
                    }
                    file_uploads.forEach((f){
                        print(f.path);
                        print(f.bytes.length);
                    });
                    
                    if (user_server_selection != null) {
                        await user_server_selection!.clear_files();
                        await upload_files(
                            files: file_uploads, 
                            file_server_canister: user_server_selection!.canister, 
                            caller: state.user!.caller, 
                            legations: state.user!.legations,
                            upload_file_method_name: 'user_upload_file',
                            upload_file_chunk_method_name: 'user_upload_file_chunk'
                        );    
                        await user_server_selection!.load_filepaths();
                    }
                    
                    
                    
                } catch(e) {
                    print('Error syncing files: $e');
                }
                setState((){
                    state.loading = false;
                });
                
                    
                    
                // print(file_uploads.map((fu)=>[fu.path, fu.content_type]).toList());
                    
            
                
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
                /*
                bottom: TabBar(
                    controller: tab_controller,
                    tabs: tabs.map((s)=>Tab(text: s)).toList()
                ),
                */
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
                child: Container(
                    padding: EdgeInsets.all(11),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                            SelectableText('welcome user: ${state.user!.principal.text}'),
                            Container(
                                width: 400,
                                child: DropdownButton(
                                    items: [
                                        DropdownMenuItem(child: Text('Create A Server'), value: null),
                                        for (UserServer user_server in state.user!.user_servers) 
                                            DropdownMenuItem(child: Text('Server: ${user_server.canister.principal.text}'), value: user_server),
                                    ],
                                    value: user_server_selection,
                                    onChanged: (UserServer? selection) {
                                        //if (selection is UserServer) {
                                            setState((){
                                                user_server_selection = selection;
                                            });
                                        //}
                                    },
                                    elevation: 0,
                                    isExpanded: true
                                ),
                            ),
                            SizedBox(
                                width: 1,
                                height: 25
                            ),
                            /*
                            Container(
                                width: 70,
                                height: 50,
                                child: HtmlElementView(
                                    viewType: 'input_directory_view_type',
                                ),
                            ),
                            */
                            if (user_server_selection == null) UserCreateServerForm(
                                state: state, 
                                change_user_server_selection_and_set_state_function: 
                                    (UserServer user_server) { 
                                        setState((){
                                            user_server_selection = user_server;
                                        });
                                    }
                            ) 
                            else ...[
                                Text('SERVER-URL:'),
                                Link(
                                    target: LinkTarget.blank,
                                    uri: Uri.parse(user_server_selection!.link),
                                    builder: (context, followLink) {
                                        return MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: GestureDetector(
                                                onTap: followLink,
                                                child: SelectableText(
                                                    user_server_selection!.link,
                                                    style: TextStyle(
                                                        color: Colors.blue,
                                                        decoration: TextDecoration.underline
                                                    )
                                                )
                                            )
                                        );
                                    }
                                ),
                                OutlinedButton(
                                    child: Text('Upload Folder', style: TextStyle(fontSize: 27)),
                                    onPressed: () {
                                        input_directory.click();
                                    }
                                ), 
                                SizedBox(
                                    height: 25
                                ),
                                Text('Browse Files:'),
                                Container(
                                    child: ServerBrowser(server: user_server_selection!) 
                                )
                            ],
                        ],
                    ),
                ),     
            )
        ); 
    }
}


class ItemUrlPolicy implements html.UriPolicy {
  RegExp regex = RegExp(r'(?:http://|https://)?.*');

  bool allowsUri(String uri) {
    return regex.hasMatch(uri);
  }
}



Future<FileUpload> file_upload_of_a_js_file(Object file) async {        
    String name = getProperty(file, 'name');
    String webkitRelativePath = getProperty(file, 'webkitRelativePath');
    int index_of_first_path_separator = webkitRelativePath.indexOf('/');
    return FileUpload(
        name: name,
        path: name == 'index.html' ? '/' : webkitRelativePath.substring(index_of_first_path_separator), //index_of_first_path_separator >= 0 ? webkitRelativePath.substring(index_of_first_path_separator) : webkitRelativePath,
        size: getProperty(file, 'size'),
        content_type: getProperty(file, 'type'),
        bytes: (await promiseToFuture(callMethod(file, 'arrayBuffer', []))).asUint8List()
    );
}




class UserCreateServerForm extends StatefulWidget {
    CustomState state;
    void Function(UserServer) change_user_server_selection_and_set_state_function;
    UserCreateServerForm({super.key, required this.state, required this.change_user_server_selection_and_set_state_function});
    
    State createState() => UserCreateServerFormState();
}
class UserCreateServerFormState extends State<UserCreateServerForm> {
    
    GlobalKey<FormState> form_key = GlobalKey<FormState>();
    
    
    late IcpTokens with_icp;
    
    
    Widget build(BuildContext context) {
        return Form(
            key: form_key,
            child: Column(
                children: <Widget>[
                    Text('User Icp Id:'),
                    SelectableText(widget.state.user!.file_server_main_user_subaccount_icp_id),
                    SizedBox(
                        width: 1,
                        height: 19,
                    ),
                    Text('Icp Balance: ${widget.state.user!.file_server_main_user_subaccount_icp_balance}'),
                    OutlinedButton(
                        child: Text('load icp balance', style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                            setState((){
                                widget.state.loading = true;
                            });
                            await widget.state.user!.load_file_server_main_user_subaccount_icp_balance();
                            setState((){
                                widget.state.loading = false;
                            });
                        }
                    ),
                    SizedBox(
                        width: 1,
                        height: 19,
                    ),
                    Text('Minimum Icp to create a server: ${CREATE_SERVER_MINIMUM_ICP}'),
                    Container(
                        constraints: BoxConstraints(maxWidth: 300),
                        child: TextFormField(
                            decoration: InputDecoration(
                                labelText: 'Create server with icp: ',
                                hintText: 'The icp converts into cycles which is the fuel that charges your server. More icp here means more cycles for your server.'
                            ),
                            onSaved: (String? value) { with_icp = IcpTokens.oftheDoubleString(value!); },
                            validator: icp_validator
                        )
                    ),
                    SizedBox(
                        width: 1,
                        height: 11,
                    ),
                    ElevatedButton(
                        child: Text('Create Server', style: TextStyle(fontSize: 27)),
                        onPressed: () async {
                            if (form_key.currentState!.validate()==true) {
                                    
                                form_key.currentState!.save();
                                
                                setState((){
                                    widget.state.loading = true;
                                });
                                
                                late UserServer user_server;
                                try {
                                    user_server = await widget.state.user!.create_server(with_icp);
                                } catch(e) {
                                    await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                            return AlertDialog(
                                                title: Text('Create Server Error:'),
                                                content: Text('${e}'),
                                                actions: <Widget>[
                                                    TextButton(
                                                        onPressed: () => Navigator.pop(context),
                                                        child: const Text('OK'),
                                                    ),
                                                ]
                                            );
                                        }   
                                    );                        
                                    setState((){
                                        widget.state.loading = false;
                                    });
                                    return;
                                }
                                
                                form_key.currentState!.reset();
                                
                                Future success_dialog = showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                        return AlertDialog(
                                            title: Text('Create Server Success:'),
                                            content: Text('server-id: ${user_server.canister.principal.text}'),
                                            actions: <Widget>[
                                                TextButton(
                                                    onPressed: () => Navigator.pop(context),
                                                    child: const Text('OK'),
                                                ),
                                            ]
                                        );
                                    }   
                                );
                                
                                
                                widget.state.user!.load_file_server_main_user_subaccount_icp_balance().then((_x){}, onError: (e) { print('error loading icp balance: $e'); });
                                
                                await success_dialog;
                                
                                widget.change_user_server_selection_and_set_state_function(user_server);
                                
                            }
                        }
                    ),
                ]
            )        
        );
    }

}

final String? Function(String?) icp_validator = (String? v) {
    if (v == null || v.trim() == '') {
        return 'Must be a number of icp tokens';
    }
    
    late IcpTokens icp;
    try {
        icp = IcpTokens.oftheDoubleString(v);
    } catch(e) {
        return 'invalid icp amount: $e';
    }
    
    return null;
    
};


class ServerBrowser extends StatefulWidget {
    final UserServer server;
    ServerBrowser({super.key, required this.server});
    State createState() => ServerBrowserState();
}
class ServerBrowserState extends State<ServerBrowser> {
    
    List<Directory> parents = [];
    late Directory directory;
    
    @override
    void initState() {
        super.initState();
        
        directory = this.widget.server.directory;
    }
    
    Widget build(BuildContext context) {
        return Container(
            child: Column(
                children: [
                    Text(directory.path),
                    ListView(
                        padding: EdgeInsets.all(4),
                        children: [
                            if (parents.length >= 1) ListTile(
                                leading: Icon(Icons.folder),
                                title: Text('..'),
                                onTap: () {
                                    setState((){
                                        directory = parents.removeLast();
                                    });
                                }
                            ),
                            for (Directory d in directory.folders) 
                                MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: ListTile(
                                        leading: Icon(Icons.folder),
                                        title: SelectableText(d.path.substring(1)),
                                        onTap: () {
                                            setState((){
                                                parents.add(directory);
                                                directory = d;
                                            });
                                        }
                                    )
                                ),
                            for (File f in directory.files) 
                                Link(
                                    target: LinkTarget.blank,
                                    uri: Uri.parse(widget.server.link + parents.map<String>((d)=>d.path).join() + f.path),
                                    builder: (context, followLink) {
                                        return MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: ListTile(
                                                leading: Icon(Icons.file_open),
                                                title: SelectableText(
                                                    parents.length == 0 && f.path == '/' ? 'index.html' : f.path.substring(1),
                                                ),
                                                onTap: followLink,
                                            )
                                        );
                                    }
                                ),
                        ]
                    ),
                ]
            )       
        );
    }
}







