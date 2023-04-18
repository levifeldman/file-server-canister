
use serde_bytes::ByteBuf;

use ic_cdk::export::{
    candid::{CandidType, Deserialize, Func, Nat}
};
use ic_certified_map::RbTree;

use std::collections::HashMap;






#[derive(CandidType, Deserialize, Clone)]
pub struct File {
    pub headers: Vec<(String, String)>,
    pub content_chunks: Vec<ByteBuf>
}
pub type Files = HashMap<String, File>;
pub type FilesHashes = RbTree<String, ic_certified_map::Hash>;




#[derive(Clone, Debug, CandidType, Deserialize)]
pub struct HttpRequest {
    pub method: String,
    pub url: String,
    pub headers: Vec<(String, String)>,
    #[serde(with = "serde_bytes")]
    pub body: Vec<u8>,
}

#[derive(Clone, Debug, CandidType)]
pub struct HttpResponse<'a> {
    pub status_code: u16,
    pub headers: Vec<(&'a str, &'a str)>,
    pub body: &'a ByteBuf,
    pub streaming_strategy: Option<StreamStrategy<'a>>,
}

#[derive(Clone, Debug, CandidType)]
pub enum StreamStrategy<'a> {
    Callback { callback: Func, token: StreamCallbackToken<'a>},
}

#[derive(Clone, Debug, CandidType, Deserialize)]
pub struct StreamCallbackToken<'a> {
    pub key: &'a str,
    pub content_encoding: &'a str,
    pub index: Nat,
    // We don't care about the sha, we just want to be backward compatible.
    //pub sha256: Option<[u8; 32]>,
}

#[derive(Clone, Debug, CandidType, Deserialize)]
pub struct StreamCallbackTokenBackwards {
    pub key: String,
    pub content_encoding: String,
    pub index: Nat,
    // We don't care about the sha, we just want to be backward compatible.
    pub sha256: Option<[u8; 32]>,
}

#[derive(Clone, Debug, CandidType)]
pub struct StreamCallbackHttpResponse<'a> {
    pub body: &'a ByteBuf,
    pub token: Option<StreamCallbackToken<'a>>,
}





#[derive(CandidType, Deserialize)]
pub struct UploadFile {
    pub path: String,
    pub headers: Vec<(String, String)>,
    pub first_chunk: ByteBuf,
    pub chunks: u32
}

#[derive(CandidType, Deserialize)]
pub struct UploadFileChunk {
    pub path: String,
    pub chunk_i: u32,
    pub chunk: ByteBuf
}

