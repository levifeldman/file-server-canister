#[cfg(test)]
mod tests;

use std::collections::HashSet;
use std::cell::RefCell;

use ic_cdk::{
    self, 
    init,
    pre_upgrade,
    post_upgrade,
    update,
    query,
    trap,
    caller,
    export::{
        Principal,
        candid::{
            CandidType,
            Deserialize,
            encode_one,
            decode_one,
            Func
        },
    },
    api::{
        call::{
            reply
        },
        stable::{
            WASM_PAGE_SIZE_IN_BYTES as WASM_PAGE_SIZE_BYTES,
            stable64_grow,
            stable64_read,
            stable64_write,
            stable64_size,
        },
    }
};

use ic_ledger_types::{
    Tokens as IcpTokens,
    BlockIndex as BlockHeight,
    TransferError as IcpTransferError
    
};

use serde_bytes::ByteBuf;
use sha2::Digest;
use num_traits::cast::ToPrimitive;





pub mod tools;
use tools::*;

pub mod types;
use types::*;

use localkey::{
    refcell::{with,with_mut},
    //cell::{set,get}
};



#[derive(CandidType, Deserialize)]
pub struct CanisterCode {
    hash: [u8; 32],
    module: ByteBuf,
}
impl CanisterCode {
    fn new() -> Self {
        Self {
            hash: [0; 32],
            module: ByteBuf::new()
        }
    }
}


pub struct UserServerData {
    canister_id: Principal,
}


#[derive(CandidType, Deserialize)]
pub struct Data {
    controllers: HashSet<Principal>,
    user_server_code: CanisterCode,
    user_servers: HashMap<Principal, Vec<UserServerData>>,
    users_create_server_mid_call_data: HashMap<Principal, UserCreateServerMidCallData>
}
impl Data {
    fn new() -> Self {
        Self {
            controllers: HashSet::new(),
            user_server_code: CanisterCode::new(),
            user_servers: HashMap::new(),
            users_create_server_mid_call_data: HashMap::new(),
        }
    }
}
impl Default for Data {
    fn default() -> Self { Self::new() }
}




thread_local! {
    pub static DATA: RefCell<Data> = RefCell::new(Data::new());
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
    let canister_data: Data = with_mut(&DATA, |data| { std::mem::take(data) });
    file_server_lib::pre_upgrade(canister_data);
}

#[post_upgrade]
fn post_upgrade() {
    let canister_data: Data = file_server_lib::post_upgrade(None);
    with_mut(&DATA, |data| {
        *data = canister_data;
    });
}



// ------------------------------------



fn caller_controller_check(caller: &Principal) {
    if with(&DATA, |data| { data.controllers.contains(caller) == false }) {
        trap("Caller must be a controller for this method");
    }
}


#[update]
pub fn controller_upload_file(q: UploadFile) {
    caller_controller_check(&caller());
    upload_file(q);
}

#[update]
pub fn controller_upload_file_chunk(q: UploadFileChunk) {
    caller_controller_check(&caller());
    upload_file_chunk(q);
}

#[update]
pub fn controller_clear_files() {
    caller_controller_check(&caller());
    clear_files();
}

// ------

#[update]
pub fn controller_upload_user_server_code(canister_code: CanisterCode) {
    caller_controller_check(&caller());
    with_mut(&DATA, |data| {
        data.user_server_code = canister_code;
    });
}



// ------



#[CandidType, Deserialize]
struct UserCreateServerMidCallData {
    lock: bool,
    // options are for the steps
    create_canister_transfer_block_height: Option<BlockHeight>, // Some() post successful transfer call
    server_canister_id: Option<Principal>,                      // Some() post successful cmc notify call
    server_canister_install_code: bool,                         // true   post successful install_code call
}


pub enum UserCreateServerError {
    IcpTransferError(IcpTransferError),
    MidCallError(UserCreateServerMidCallError),
}

pub enum UserCreateServerMidCallError {
    CMCNotifyCreateCanisterError(),
    InstallCodeError((u32, String))
}

#[update]
pub async fn user_create_server(with_icp: IcpTokens) -> Result<UserCreateServerSuccess, UserCreateServerError> {
    
    // check if ongoing call data, if yes, if ongoing call data .lock == true: return ongoing call, if ongoing call data .lock == false: turn lock on, put ongoing call data into the hashmap.
    
    // try to send the transfer, if fail delete ongoing call data and return final-error
    
    // try to call notify on the cmc, if fail unlock call data, keep call data in a hashmap and return mid-call-error
    
    // try to install_code, if success delete mid-call-data, put canister into user_servers map, and return user_server_canister_id. if fail, unlock call data, keep call data in mid-call-data-map, and return mid-call-error 
        
}





// --------





#[query(manual_reply = true)]
pub fn see_user_server_canister_ids() { //-> Vec<&Principal> {
    with(&DATA, |data| {
        reply::<(Vec<&Principal>,)>((data.user_servers.get(&caller()).iter().collect::<Vec<&Principal>>(),));
    });
}



// upgrade user servers



