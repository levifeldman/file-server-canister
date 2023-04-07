#[cfg(test)]
mod tests;

use std::collections::HashSet;
use ic_cdk::{
    self, 
    api::{
        call,
    }
};
use ic_cdk_macros::{
    update,
    query,
};




const 
const STABLE_MEMORY_HEADER_SIZE_BYTES: u64 = 1024;



pub struct Data {
    controllers: HashSet<Principal>,
    files: Files,
    files_hashes: Vec<(String, [u8; 32])>, // field is only use for the upgrades.
}
impl Data {
    fn new() -> Self {   
        files: Files::new(),
        files_hashes: Vec::new(), // field is only use for the upgrades.
    }
}




thread_local! {
    pub static DATA: RefCell<CTSData> = RefCell::new(Data::new());
    
    // not save through upgrades
    pub static FILES_HASHES: RefCell<FilesHashes> = RefCell::new(FilesHashes::new()); // save through the upgrades by the files_hashes field on the Data struct
    static     STATE_SNAPSHOT: RefCell<Vec<u8>> = RefCell::new(Vec::new());    
}


#[derive(CandidType, Deserialize)]
pub struct Init {
    controllers: HashSet<Principal>,
}

#[init]
fn init(q: Init) {
    with_mut(&DATA, |data| {
        data.controllers = q.controllers;
    });
}

#[pre_upgrade]
fn pre_upgrade() {
    
    create_state_snapshot();
    
    let current_stable_size_wasm_pages: u64 = stable64_size();
    let current_stable_size_bytes: u64 = current_stable_size_wasm_pages * WASM_PAGE_SIZE_BYTES as u64;

    with(&STATE_SNAPSHOT, |state_snapshot| {
        let want_stable_memory_size_bytes: u64 = STABLE_MEMORY_HEADER_SIZE_BYTES + 8/*len of the state_snapshot*/ + state_snapshot.len() as u64; 
        if current_stable_size_bytes < want_stable_memory_size_bytes {
            stable64_grow(((want_stable_memory_size_bytes - current_stable_size_bytes) / WASM_PAGE_SIZE_BYTES as u64) + 1).unwrap();
        }
        stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES, &((state_snapshot.len() as u64).to_be_bytes()));
        stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES + 8, state_snapshot);
    });

}

#[post_upgrade]
fn post_upgrade() {
    let mut state_snapshot_len_u64_be_bytes: [u8; 8] = [0; 8];
    stable64_read(STABLE_MEMORY_HEADER_SIZE_BYTES, &mut state_snapshot_len_u64_be_bytes);
    let state_snapshot_len_u64: u64 = u64::from_be_bytes(state_snapshot_len_u64_be_bytes); 
    
    with_mut(&STATE_SNAPSHOT, |state_snapshot| {
        *state_snapshot = vec![0; state_snapshot_len_u64 as usize]; 
        stable64_read(STABLE_MEMORY_HEADER_SIZE_BYTES + 8, state_snapshot);
    });
    
    load_state_snapshot_data();

}


fn create_state_snapshot() {
    with_mut(&DATA, |data| {
        data.files_hashes = with(&FILES_HASHES, |files_hashes| { 
            files_hashes.iter().map(
                |(name, hash)| { (name.clone(), hash.clone()) }
            ).collect::<Vec<(String, [u8; 32])>>() 
        });
    });
    
    let data_candid_bytes: Vec<u8> = with(&DATA, |data| { encode_one(data).unwrap() });
    
    with_mut(&STATE_SNAPSHOT, |state_snapshot| {
        *state_snapshot = data_candid_bytes; 
    });
}

fn load_state_snapshot_data() {
    
    let mut data_of_the_state_snapshot: Data = with(&STATE_SNAPSHOT, |state_snapshot| {
        match decode_one::<Data>(state_snapshot) {
            Ok(data) => data,
            Err(_) => {
                trap("error decode of the state-snapshot Data");
                /*
                let old_data: OldData = decode_one::<OldData>(state_snapshot).unwrap();
                let data: Data = Data{
                    controllers: old_data.controllers,
                    ...
                };
                data
                */
            }
        }
    });

    with_mut(&FILES_HASHES, |files_hashes| {
        *files_hashes = FilesHashes::from_iter(data_of_the_state_snapshot.files_hashes.drain(..));
        set_root_hash(files_hashes);
    });

    with_mut(&DATA, |data| {
        *data = data_of_the_state_snapshot;    
    });
    
}






#[derive(CandidType, Deserialize)]
pub struct UploadFile {
    pub path: String,
    pub headers: Vec<(String, String)>,
    pub first_chunk: ByteBuf,
    pub chunks: u32
}

#[update]
pub fn controller_upload_file(q: UploadFile) {
    caller_controller_check(&caller());
    
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

    with_mut(&DATA, |data| {        
        data.files.insert(
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

#[update]
pub fn controller_upload_file_chunks(path: String, chunk_i: u32, chunk: ByteBuf) -> () {
    caller_controller_check(&caller());
    
    with_mut(&DATA, |DATA| {
        match DATA.files.get_mut(&path) {
            Some(file) => {
                file.content_chunks[chunk_i.try_into().unwrap()] = chunk;
                
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
                            path.clone(), 
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
                trap("file not found. call the controller_upload_file method to upload a new file.");
            }
        }
    });
    
}


#[update]
pub fn controller_clear_files() {
    caller_controller_check(&caller());
    
    with_mut(&DATA, |DATA| {
        DATA.files = Files::new();
    });

    with_mut(&FILES_HASHES, |fhs| {
        *fhs = FilesHashes::new();
        set_root_hash(fhs);
    });
}

#[update]
pub fn controller_clear_file(path: String) {
    caller_controller_check(&caller());
    
    with_mut(&DATA, |DATA| {
        DATA.files.remove(&path);
    });

    with_mut(&FILES_HASHES, |fhs| {
        fhs.delete(path.as_bytes());
        set_root_hash(fhs);
    });
}



#[query]
pub fn controller_get_file_hashes() -> Vec<(String, [u8; 32])> {
    caller_controller_check(&caller());
    
    with(&FILES_HASHES, |file_hashes| { 
        let mut vec = Vec::<(String, [u8; 32])>::new();
        file_hashes.for_each(|k,v| {
            vec.push((std::str::from_utf8(k).unwrap().to_string(), *v));
        });
        vec
    })
}



#[query(manual_reply = true)]
pub fn http_request(quest: HttpRequest) {
    
    let path: &str = quest.url.split("?").next().unwrap();
    
    with(&DATA, |DATA| {
        match DATA.files.get(path) {
            None => {
                reply::<(HttpResponse,)>(
                    (HttpResponse {
                        status_code: 404,
                        headers: vec![],
                        body: &ByteBuf::from(vec![]),
                        streaming_strategy: None
                    },)
                );        
            }, 
            Some(file) => {
                let (file_certificate_header_key, file_certificate_header_value): (String, String) = make_file_certificate_header(path); 
                let mut headers: Vec<(&str, &str)> = vec![(&file_certificate_header_key, &file_certificate_header_value),];
                headers.extend(file.headers.iter().map(|tuple: &(String, String)| { (&tuple.0, &tuple.1) }));
                reply::<(HttpResponse,)>(
                    (HttpResponse {
                        status_code: 200,
                        headers: headers, 
                        body: &file.content_chunks[0],
                        streaming_strategy: if let Some(stream_callback_token) = create_opt_stream_callback_token(path, file, 0) {
                            Some(StreamStrategy::Callback{ 
                                callback: Func{
                                    principal: ic_cdk::api::id(),
                                    method: "http_request_stream_callback".to_string(),
                                },
                                token: stream_callback_token 
                            })
                        } else {
                            None
                        }
                    },)
                );
            }
        }
    });
    
}



#[query(manual_reply = true)]
fn http_request_stream_callback(token: StreamCallbackTokenBackwards) {    
    with(&DATA, |DATA| {
        match DATA.files.get(&token.key) {
            None => {
                trap("the file is not found");        
            }, 
            Some(file) => {
                let chunk_i: usize = token.index.0.to_usize().unwrap_or_else(|| { trap("invalid index"); }); 
                reply::<(StreamCallbackHttpResponse,)>((StreamCallbackHttpResponse {
                    body: &file.content_chunks[chunk_i],
                    token: create_opt_stream_callback_token(&token.key, file, chunk_i),
                },));
            }
        }
    })
}


