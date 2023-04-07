import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:html' as html;  
import 'package:js/js_util.dart';


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
            (html.Event event) {
                for (Object file in getProperty(getProperty(event, 'target'), 'files')) {
                    print(getProperty(file, 'webkitRelativePath'));
                }
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
                child: Text('upload folder'),
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
