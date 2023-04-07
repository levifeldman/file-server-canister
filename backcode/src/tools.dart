use std::collections::HashMap;
use ic_cdk::{
    export::candid::{CandidType, Deserialize, Func, Nat},
    api::{data_certificate, set_certified_data}
};
use ic_certified_map::{self, HashTree, AsHashTree};






pub fn sha256(bytes: &[u8]) -> [u8; 32] {
    let mut hasher: sha2::Sha256 = sha2::Sha256::new();
    hasher.update(bytes);
    hasher.finalize().into()
}


pub mod localkey {
    pub mod refcell {
        use std::{
            cell::RefCell,
            thread::LocalKey,
        };
        pub fn with<T: 'static, R, F>(s: &'static LocalKey<RefCell<T>>, f: F) -> R
        where 
            F: FnOnce(&T) -> R 
        {
            s.with(|b| {
                f(&*b.borrow())
            })
        }
        
        pub fn with_mut<T: 'static, R, F>(s: &'static LocalKey<RefCell<T>>, f: F) -> R
        where 
            F: FnOnce(&mut T) -> R 
        {
            s.with(|b| {
                f(&mut *b.borrow_mut())
            })
        }
    }
    pub mod cell {
        use std::{
            cell::Cell,
            thread::LocalKey
        };
        pub fn get<T: 'static + Copy>(s: &'static LocalKey<Cell<T>>) -> T {
            s.with(|c| { c.get() })
        }
        pub fn set<T: 'static + Copy>(s: &'static LocalKey<Cell<T>>, v: T) {
            s.with(|c| { c.set(v); });
        }
    }
}




pub fn caller_controller_check(caller: &Principal) {
    if with(&DATA, |data| { data.controllers.contains(caller) }) == false {
        trap("Caller must be a controller for this method.")
    }
}

















use crate::FRONTCODE_FILES_HASHES;

const LABEL_ASSETS: &[u8; 11] = b"http_assets";





pub fn set_root_hash(tree: &FilesHashes) {
    let root_hash = ic_certified_map::labeled_hash(LABEL_ASSETS, &tree.root_hash());
    set_certified_data(&root_hash[..]);
}


pub fn make_file_certificate_header(path: &str) -> (String, String) {
    let certificate: Vec<u8> = data_certificate().unwrap_or(vec![]);
    with(&FRONTCODE_FILES_HASHES, |ffhs| {
        let witness: HashTree = ffhs.witness(path.as_bytes());
        let tree: HashTree = ic_certified_map::labeled(LABEL_ASSETS, witness);
        let mut serializer = serde_cbor::ser::Serializer::new(vec![]);
        serializer.self_describe().unwrap();
        tree.serialize(&mut serializer).unwrap();
        (
            "IC-Certificate".to_string(),
            format!("certificate=:{}:, tree=:{}:",
                base64::encode(&certificate),
                base64::encode(&serializer.into_inner())
            )
        )
    })
}


pub fn create_opt_stream_callback_token<'a>(path: &'a str, file: &'a File, chunk_i: usize) -> Option<StreamCallbackToken<'a>> {
    if file.content_chunks.len() > chunk_i + 1 {
        Some(StreamCallbackToken{
            key: path,
            content_encoding: file.headers.iter().find(|header| { header.0.eq_ignore_ascii_case("Content-Encoding") }).map(|header| { &*(header.1) }).unwrap_or(""),
            index: Nat::from(chunk_i + 1),
            /*
            sha256: {
                with(&FILES_HASHES, |fhs| {
                    fhs.get(path.as_bytes())
                    .map(|hash| { hash.clone() })
                })  
            }
            */
        })
    } else {
        None
    }
}
