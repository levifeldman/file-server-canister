


use ic_cdk::{
    export::{
        candid::{
            CandidType,
            Deserialize
        }
    },
    trap
};

use serde_bytes::ByteBuf;

use sha2::Digest;

use crate::{
    tools::{
        localkey::{
            refcell::{
                with,
                with_mut,
            }
        },
        sha256,
        set_root_hash
    },
    data::{
        FILES_HASHES,
        FILES,
    },
    types::{
        File,
        Files,
        FilesHashes
    }
};



#[derive(CandidType, Deserialize)]
pub struct UploadFile {
    pub path: String,
    pub headers: Vec<(String, String)>,
    pub first_chunk: ByteBuf,
    pub chunks: u32
}


pub fn upload_file(q: UploadFile) {
    
    if q.chunks == 0 {
        trap("there must be at least 1 chunk.");
    }
    
    if q.chunks == 1 {
        with_mut(&FILES_HASHES, |fhs| {
            fhs.insert(
                q.path.clone(), 
                sha256(&q.first_chunk)
            );
            set_root_hash(fhs);
        });
    }

    with_mut(&FILES, |files| {        
        files.insert(
            q.path, 
            File{
                headers: q.headers,
                content_chunks: {
                    let mut v: Vec<ByteBuf> = vec![ByteBuf::new(); q.chunks.try_into().unwrap()];
                    v[0] = q.first_chunk;
                    v
                }
            }
        ); 
    });

}

#[derive(CandidType, Deserialize)]
pub struct UploadFileChunk {
    path: String,
    chunk_i: u32,
    chunk: ByteBuf
}



fn upload_file_chunk(q: UploadFileChunk) {
    with_mut(&FILES, |files| {
        match files.get_mut(&q.path) {
            Some(file) => {
                file.content_chunks[<u32 as TryInto<usize>>::try_into(q.chunk_i).unwrap()] = q.chunk;
                
                let mut is_upload_complete: bool = true;
                for c in file.content_chunks.iter() {
                    if c.len() == 0 {
                        is_upload_complete = false;
                        break;
                    }
                }
                if is_upload_complete == true {
                    with_mut(&FILES_HASHES, |fhs| {
                        fhs.insert(
                            q.path.clone(), 
                            {
                                let mut hasher: sha2::Sha256 = sha2::Sha256::new();
                                for chunk in file.content_chunks.iter() {
                                    hasher.update(chunk);    
                                }
                                hasher.finalize().into()
                            }
                        );
                        set_root_hash(fhs);
                    });
                }
            },
            None => {
                //return Err(UploadFileChunkError::FileNotFound);
                trap("file not found. call the upload_file method first to upload a new file.");
            }
        }
    });
    
}





pub fn clear_files() {

    with_mut(&FILES, |files| {
        *files = Files::new();
    });

    with_mut(&FILES_HASHES, |fhs| {
        *fhs = FilesHashes::new();
        set_root_hash(fhs);
    });
}


pub fn clear_file(path: &String) {
    
    with_mut(&FILES, |files| {
        files.remove(path);
    });

    with_mut(&FILES_HASHES, |fhs| {
        fhs.delete(path.as_bytes());
        set_root_hash(fhs);
    });
}





pub fn get_file_hashes() -> Vec<(String, [u8; 32])> {    
    with(&FILES_HASHES, |file_hashes| { 
        let mut vec = Vec::<(String, [u8; 32])>::new();
        file_hashes.for_each(|k,v| {
            vec.push((std::str::from_utf8(k).unwrap().to_string(), *v));
        });
        vec
    })
}


pub fn get_file_hash(path: &str) -> Option<[u8; 32]> {    
    with(&FILES_HASHES, |file_hashes| { 
        file_hashes.get(path.as_bytes()).copied()
    })
}

pub fn see_filepaths() -> Vec<String> {
    with(&FILES, |files| {
        files.keys().map(|path: &String| { path.clone() }).collect::<Vec<String>>()
    })
}

