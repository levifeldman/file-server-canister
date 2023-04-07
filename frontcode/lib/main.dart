import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:html' as html;  
import 'package:js/js_util.dart';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Server',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
    late html.Element input_directory;  
  
    @override
    void initState() {
        super.initState();
    
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
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
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
