use std::cell::RefCell;

use ic_cdk::{
    init,
    pre_upgrade,
    post_upgrade,
    update,
    //query,
    caller,
    trap,
    export::{
        Principal,
        candid::{
            CandidType,
            Deserialize
        }
    }
};

use file_server_lib::{
    types::{
        UserServerInit,
        UploadFile,
        UploadFileChunk,
    },
    files::{
        upload_file,
        upload_file_chunk,
        clear_files
    },
    tools::{
        localkey::refcell::{with, with_mut},
    }
};


#[derive(CandidType, Deserialize)]
pub struct OldData {}


#[derive(CandidType, Deserialize)]
pub struct Data {
    user_id: Principal
}
impl Data {
    fn new() -> Self {
        Self {
            user_id: Principal::from_slice(&[]),
        }
    }
}
impl Default for Data {
    fn default() -> Self { Self::new() }
}




thread_local! {
    pub static DATA: RefCell<Data> = RefCell::new(Data::new());
}


#[init]
fn init(q: UserServerInit) {
    with_mut(&DATA, |data| {
        data.user_id = q.user_id;
    });
}

#[pre_upgrade]
fn pre_upgrade() {
    let canister_data: Data = with_mut(&DATA, |data| { std::mem::take(data) });
    file_server_lib::pre_upgrade(canister_data);
}

#[post_upgrade]
fn post_upgrade() {
    let canister_data: Data = file_server_lib::post_upgrade(None::<fn(OldData) -> Data>);
    with_mut(&DATA, |data| {
        *data = canister_data;
    });
}

// ------------------------------------


fn caller_is_user_check(caller: &Principal) {
    if with(&DATA, |data| { (&(data.user_id) == caller) == false }) {
        trap("Caller must be the owner of this server");
    }
}


#[update]
pub fn user_upload_file(q: UploadFile) {
    caller_is_user_check(&caller());
    upload_file(q);
}

#[update]
pub fn user_upload_file_chunk(q: UploadFileChunk) {
    caller_is_user_check(&caller());
    upload_file_chunk(q);
}

#[update]
pub fn user_clear_files() {
    caller_is_user_check(&caller());
    clear_files();
}

// ------





