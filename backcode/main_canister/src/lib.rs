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
use management_canister::{self, *};



use file_server_lib::tools::localkey::{
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

#[derive(CandidType, Deserialize)]
pub struct UserServerData {
    canister_id: Principal,
    module_hash: [u8; 32],
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

const MAX_USERS_CREATE_SERVER_AT_THE_SAME_TIME: usize = 1000;
const CREATE_SERVER_MINIMUM_ICP: IcpTokens = IcpTokens::from_e8s(50_000_000);
const TAKE_CYCLES_PAYMENT_FOR_THE_CREATION_OF_A_USER_SERVER: Cycles = 1_000_000_000_000;




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


pub struct UserIsInTheMiddleOfADifferentCall{
    kind: UserIsInTheMiddleOfADifferentCallKind,
    must_call_continue: bool
}

pub enum UserIsInTheMiddleOfADifferentCallKind {
    UserCreateServer
}






// ----

#[derive(CandidType, Deserialize, Clone)]
struct UserCreateServerMidCallData {
    start_time_nanos: u64,
    lock: bool,
    user_create_server_quest: UserCreateServerQuest,
    // options are for the steps
    topup_cycles_ledger_transfer_block_height: Option<IcpBlockHeight>,  // Some() post successful topup_cycles_ledger_transfer call
    topup_cycles: Option<Cycles>,                                       // Some() post successful cmc_notify_topup call
    server_canister_id: Option<Principal>,                              // Some() post successful management create_canister call
    server_canister_module_hash: Option<[u8; 32]>,                      // Some() post successful install_code call
}

#[derive(CandidType, Deserialize)]
pub struct UserCreateServerQuest {
    with_icp: IcpTokens,   
}

#[derive(CandidType, Deserialize)]
pub struct UserCreateServerSuccess {
    server_canister_id: Principal,   
}

#[derive(CandidType, Deserialize)]
pub enum UserCreateServerError {
    CreateServerMinimumIcp(IcpTokens),
    UserIsInTheMiddleOfADifferentCall(UserIsInTheMiddleOfADifferentCall),
    Busy,
    TopUpCyclesLedgerTransferError(TopUpCyclesLedgerTransferError),
    MidCallError(UserCreateServerMidCallError),
}

#[derive(CandidType, Deserialize)]
pub enum UserCreateServerMidCallError {
    TopUpCyclesCmcNotifyError(TopUpCyclesCmcNotifyError),
    CreateCanisterCallError((u32, String)),
    InstallCodeCallError((u32, String))
}


fn unlock_and_write_user_create_server_mid_call_data(user_id: Principal, mut user_create_server_mid_call_data: UserCreateServerMidCallData) {
    user_create_server_mid_call_data.lock = false;
    with_mut(&DATA, |data| {
        data.users_create_server_mid_call_data.insert(user_id, user_create_server_mid_call_data);
    });
}



#[update]
pub async fn user_create_server(q: UserCreateServerQuest) -> Result<UserCreateServerSuccess, UserCreateServerError> {
    
    let user_id: Principal = caller();
    
    if q.with_icp < CREATE_SERVER_MINIMUM_ICP {
        return Err(UserCreateServerError::CreateServerMinimumIcp(CREATE_SERVER_MINIMUM_ICP));
    }
    
    let user_create_server_mid_call_data: UserCreateServerMidCallData = with_mut(&DATA, |data| {
        match data.users_create_server_mid_call_data.get(&user_id) {
            Some(user_create_server_mid_call_data) => {
                return Err(UserCreateServerError::UserIsInTheMiddleOfADifferentCall(UserIsInTheMiddleOfADifferentCall{ 
                    kind: UserIsInTheMiddleOfADifferentCallKind::UserCreateServer, 
                    must_call_continue: !user_create_server_mid_call_data.lock 
                }));   
            },
            None => {
                if data.users_create_server_mid_call_data.len() >= MAX_USERS_CREATE_SERVER_AT_THE_SAME_TIME {
                    return Err(UserCreateServerError::Busy);
                }
                let user_create_server_mid_call_data: UserCreateServerMidCallData = UserCreateServerMidCallData{
                    start_time_nanos: time(),
                    lock: true,
                    user_create_server_quest: q,
                    topup_cycles_ledger_transfer_block_height: None,
                    topup_cycles: None,
                    server_canister_id: None,
                    server_canister_module_hash: None,       
                };
                data.users_create_server_mid_call_data.insert(user_id, user_create_server_mid_call_data.clone());
                Ok(user_create_server_mid_call_data)
            }
        }
    })?;
    
    user_create_server_(user_id, user_create_server_mid_call_data).await
        
}


async fn user_create_server_(user_id: Principal, mut user_create_server_mid_call_data: UserCreateServerMidCallData) 
-> Result<UserCreateServerSuccess, UserCreateServerError> {

    // send the transfer, if fail delete ongoing call data and return final-error
    if user_create_server_mid_call_data.topup_cycles_ledger_transfer_block_height.is_none() {
        match topup_cycles_ledger_transfer(
            user_create_server_mid_call_data.user_create_canister_quest.with_icp,
            Some(principal_icp_subaccount(user_id)),
            ic_cdk::api::id()
        ).await {
            Ok(block_height) => {
                user_create_server_mid_call_data.topup_cycles_ledger_transfer_block_height = Some(block_height);
            },
            Err(topup_cycles_ledger_transfer_error) => {
                with_mut(&DATA, |data| {
                    data.users_create_server_mid_call_data.remove(&user_id);
                });
                return Err(UserCreateServerError::TopUpCyclesLedgerTransferError(topup_cycles_ledger_transfer_error));
            }
        }
    }
    
    // call notify on the cmc, if fail unlock call data, write mid call data in the hashmap and return mid-call-error
    if user_create_server_mid_call_data.topup_cycles.is_none() {
        match topup_cycles_cmc_notify(
            user_create_server_mid_call_data.topup_cycles_ledger_transfer_block_height.unwrap(),
            ic_cdk::api::id()
        ).await {
            Ok(topup_cycles) => {
                user_create_server_mid_call_data.topup_cycles = Some(topup_cycles);
            },
            Err(topup_cycles_cmc_notify_error) => {
                unlock_and_write_user_create_server_mid_call_data(user_id, user_create_server_mid_call_data);
                return Err(UserCreateServerError::MidCallError(UserCreateServerMidCallError::TopUpCyclesCmcNotifyError(topup_cycles_cmc_notify_error)));
            }
        }
    }
    
    // create a canister using management canister create_canister method
    if user_create_server_mid_call_data.server_canister_id.is_none() {
        management_canister::create_canister(
            CreateCanisterQuest{
                settings: None
            },
            user_create_server_mid_call_data.topup_cycles.unwrap().saturating_sub(TAKE_CYCLES_PAYMENT_FOR_THE_CREATION_OF_A_USER_SERVER)
        ).await {
            Ok(canister_id_record) => {
                user_create_server_mid_call_data.server_canister_id = Some(canister_id_record.canister_id);
            },
            Err(create_canister_call_error) => {
                unlock_and_write_user_create_server_mid_call_data(user_id, user_create_server_mid_call_data);
                return Err(UserCreateServerError::MidCallError(UserCreateServerMidCallError::CreateCanisterCallError(create_canister_call_error)));
            }
        }
    }
    
    // install_code, if success delete mid-call-data, put canister into user_servers map, and return user_server_canister_id. if fail, unlock call data, keep call data in mid-call-data-map, and return mid-call-error 
    if user_create_server_mid_call_data.server_canister_module_hash.is_none() {
        let (module_hash, call_future): ([u8; 32], _) = with(&DATA, |data| {
            (
                data.user_server_code.hash,
                management_canister::install_code(
                    InstallCodeQuest{
                        mode: InstallCodeMode::install,
                        canister_id: user_create_server_mid_call_data.server_canister_id.unwrap(),
                        wasm_module: &(data.user_server_code.module),
                        arg: todo!()
                    }
                )
            )
        });
        match call_future.await {
            Ok(()) => {
                user_create_server_mid_call_data.server_canister_module_hash = Some(module_hash);
            },
            Err(install_code_call_error) => {
                unlock_and_write_user_create_server_mid_call_data(user_id, user_create_server_mid_call_data);
                return Err(UserCreateServerError::MidCallError(UserCreateServerMidCallError::InstallCodeCallError(install_code_call_error)));
            }
        }
    }   
    
    let user_server_data: UserServerData = UserServerData{
        canister_id: user_create_server_mid_call_data.server_canister_id.unwrap(),
        module_hash: user_create_server_mid_call_data.server_canister_module_hash.unwrap()    
    };
    
    with_mut(&DATA, |data| {
        match data.user_servers.get_mut(&user_id) {
            None => {
                data.user_servers.insert(user_id, vec![user_server_data]);
            },
            Some(servers_of_the_user) => {
                servers_of_the_user.push(user_server_data);
            }
        }
        
        data.user_create_server_mid_call_data.remove(&user_id);
    });
    
    UserCreateServerSuccess{
        server_canister_id: user_create_server_mid_call_data.server_canister_id.unwrap(),   
    }
}


#[derive(CandidType, Deserialize)]
pub enum ContinueUserCreateServerError {
    CallerIsNotInTheMiddleOfAUserCreateServerCall,
    UserCreateServerError(UserCreateServerError),
}

#[update]
pub async fn continue_user_create_server() -> Result<UserCreateServerSuccess, ContinueUserCreateServerError> {
    
    continue_user_create_server_(caller()).await

}

async fn continue_user_create_server_(user_id: Principal) -> Result<UserCreateServerSuccess, ContinueUserCreateServerError> {
    
    let user_create_server_mid_call_data: UserCreateServerMidCallData = with_mut(&DATA, |data| {
        match data.users_create_server_mid_call_data.get_mut(&user_id) {
            Some(user_create_server_mid_call_data) => {
                if user_create_server_mid_call_data.lock == true {
                    return Err(ContinueUserCreateServerError::UserCreateServerError(
                        UserCreateServerError::UserIsInTheMiddleOfADifferentCall(UserIsInTheMiddleOfADifferentCall{ 
                            kind: UserIsInTheMiddleOfADifferentCallKind::UserCreateServer, 
                            must_call_continue: false 
                        })
                    ));
                }
                user_create_server_mid_call_data.lock = true;
                Ok(user_create_server_mid_call_data.clone())
            },
            None => {
                return Err(ContinueUserCreateServerError::CallerIsNotInTheMiddleOfAUserCreateServerCall);
            }
        }
    })?;

    user_create_server_(user_id, user_create_server_mid_call_data).await
        .map_err(|user_create_server_error| { 
            ContinueUserCreateServerError::UserCreateServerError(user_create_server_error) 
        })
        
}






// --------





#[query(manual_reply = true)]
pub fn see_user_server_canister_ids() { //-> Vec<&Principal> {
    with(&DATA, |data| {
        reply::<(Vec<&Principal>,)>((
            data.user_servers.get(&caller()).unwrap_or(&vec![])
            .iter()
            .map(|user_server_data: &&UserServerData| { 
                &(user_server_data.canister_id)
            })
            .collect::<Vec<&Principal>>()
        ,));
    });
}



// upgrade user servers



