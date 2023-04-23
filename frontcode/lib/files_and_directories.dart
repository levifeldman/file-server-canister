import 'package:tuple/tuple.dart';




void main() {
    List<String> filepaths = [
        '/',
        '/home/levi',
        '/home/house',
        '/home/love/wonder',
        '/home/love/yang',
        '/one/two/three',
        '/one/two/four'
    ];
  
    try {
        Tuple2<List<File>, List<Directory>> files_and_folders = 
        files_and_folders_of_the_filepaths(filepaths);
        print(print_directory(Directory(
            path: '/',
            files: files_and_folders.item1,
            folders: files_and_folders.item2
        ), 0));
    } catch(e, s) {
        print(e);
        print(s);
    }
}




class File {
    final String path;
    File({required this.path});
    
}
class Directory {
    String path;
    List<File> files;
    List<Directory> folders;
    
    Directory({required this.path, required this.files, required this.folders});
    
    String get name => this.path.substring(this.path.lastIndexOf('/') + 1);
}

Tuple2<List<File>, List<Directory>> files_and_folders_of_the_filepaths(List<String> filepaths) {
    List<File> files = [];
    List<Directory> folders = [];
    
    for (String filepath in filepaths) {
        
        List<String> filepath_split = filepath.split('/');
        if (filepath_split.length == 2) {
            files.add(
                File(
                    path: filepath
                )
            );
        }
        else if (filepath_split.length > 2) {
            String directory_path = '/' + filepath.substring(1).substring(0, filepath.substring(1).indexOf('/'));            
            if (folders.map<String>((d)=>d.path).toList().contains(directory_path) == false) {
                Tuple2<List<File>, List<Directory>> files_and_folders = files_and_folders_of_the_filepaths(
                    filepaths
                    .where((fp)=>fp.length >= directory_path.length && fp.substring(0, directory_path.length) == directory_path)
                    .map((fp)=>fp.substring(directory_path.length)).toList()
                );
                folders.add(
                    Directory(
                        path: directory_path,
                        files: files_and_folders.item1,
                        folders: files_and_folders.item2
                    )
                );
            }
        
        }
    }
    
    return Tuple2<List<File>, List<Directory>>(
        files, 
        folders
    );
}

String print_directory(Directory d, [int depth = 0]) {
    String tabs = '';
    for (int i = 0; i < depth; i++) {
        tabs = tabs + '\t';
    }
    String s = 'Directory: ${d.path}';
    d.files.forEach((File file){
        s = s + '\n\t${tabs}File: ${file.path}';
    });
    d.folders.forEach((Directory folder){
        s = s + '\n\t${tabs}${print_directory(folder, depth + 1)}';
    });
    return s;
}

