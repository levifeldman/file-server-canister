

use ic_ledger_types::{
    Tokens as IcpTokens,
    BlockIndex as IcpBlockHeight,
    MAINNET_CYCLES_MINTING_CANISTER_ID,
    MAINNET_LEDGER_CANISTER_ID,
    DEFAULT_FEE as ICP_LEDGER_TRANSFER_DEFAULT_FEE,
    transfer as icp_transfer,
    TransferArgs as IcpTransferArgs
    TransferError as IcpTransferError,
    Subaccount as IcpSubaccount
};








pub fn principal_as_thirty_bytes(p: &Principal) -> [u8; 30] {
    let mut bytes: [u8; 30] = [0; 30];
    let p_bytes: &[u8] = p.as_slice();
    bytes[0] = p_bytes.len() as u8; 
    bytes[1 .. p_bytes.len() + 1].copy_from_slice(p_bytes); 
    bytes
}

pub fn thirty_bytes_as_principal(bytes: &[u8; 30]) -> Principal {
    Principal::from_slice(&bytes[1..1 + bytes[0] as usize])
} 


#[test]
fn thirty_bytes_principal() {
    let test_principal: Principal = Principal::from_slice(&[0,1,2,3,4,5,6,7,8,9]);
    assert_eq!(test_principal, thirty_bytes_as_principal(&principal_as_thirty_bytes(&test_principal)));
}




pub fn principal_icp_subaccount(principal: &Principal) -> IcpSubaccount {
    let mut sub_bytes = [0u8; 32];
    sub_bytes[..30].copy_from_slice(&principal_as_thirty_bytes(principal));
    IcpSubaccount(sub_bytes)
}
















pub type Cycles = u128;

#[derive(CandidType, Deserialize)]
pub struct CmcNotifyCreateCanisterQuest {
    pub block_index: IcpBlockHeight,
    pub controller: Principal,
}

#[derive(CandidType, Deserialize)]
pub struct CmcNotifyTopUpQuest {
    pub block_index: IcpBlockHeight,
    pub canister_id: Principal,
}

#[derive(CandidType, Deserialize)]
pub enum CmcNotifyError {
    Refunded { block_index: Option<IcpBlockHeight>, reason: String },
    InvalidTransaction(String),
    Other{ error_message: String, error_code: u64 },
    Processing,
    TransactionTooOld(IcpBlockHeight),
}

pub type CmcNotifyCreateCanisterResult = Result<Principal, CmcNotifyError>;

pub type CmcNotifyTopUpResult = Result<Cycles, CmcNotifyError>;




#[derive(CandidType, Deserialize)]
pub enum TopUpCyclesLedgerTransferError {
    IcpTransferCallError((u32, String)),
    IcpTransferError(IcpTransferError),
}

pub async fn topup_cycles_ledger_transfer(icp: IcpTokens, from_subaccount: Option<IcpSubaccount>, topup_canister: Principal) -> Result<IcpBlockHeight, TopUpCyclesLedgerTransferError> {

}




    let cmc_icp_transfer_block_height: IcpBlockHeight = match icp_transfer(
        MAINNET_LEDGER_CANISTER_ID,
        IcpTransferArgs {
            memo: ICP_LEDGER_TOP_UP_CANISTER_MEMO,
            amount: icp,                              
            fee: ICP_LEDGER_TRANSFER_DEFAULT_FEE,
            from_subaccount: from_subaccount,
            to: IcpId::new(&MAINNET_CYCLES_MINTING_CANISTER_ID, &principal_icp_subaccount(&topup_canister)),
            created_at_time: Some(IcpTimestamp { timestamp_nanos: time() })
        }
    ).await {
        Ok(transfer_call_sponse) => match transfer_call_sponse {
            Ok(block_index) => block_index,
            Err(transfer_error) => {
                return Err(LedgerTopupCyclesCmcIcpTransferError::IcpTransferError(transfer_error));
            }
        },
        Err(transfer_call_error) => {
            return Err(LedgerTopupCyclesCmcIcpTransferError::IcpTransferCallError((transfer_call_error.0 as u32, transfer_call_error.1)));
        }
    };
    
    Ok(cmc_icp_transfer_block_height)
}


#[derive(CandidType, Deserialize)]
pub enum LedgerTopupCyclesCmcNotifyError {
    CmcNotifyTopUpQuestCandidEncodeError(String),
    CmcNotifyCallError((u32, String)),
    CmcNotifySponseCandidDecodeError{candid_error: String, candid_bytes: Vec<u8>},
    CmcNotifyError(CmcNotifyError),
}

pub async fn ledger_topup_cycles_cmc_notify(cmc_icp_transfer_block_height: IcpBlockHeight, topup_canister_id: Principal) -> Result<Cycles, LedgerTopupCyclesCmcNotifyError> {

    let topup_cycles_cmc_notify_call_candid: Vec<u8> = match encode_one(
        & CmcNotifyTopUpCyclesQuest {
            block_index: cmc_icp_transfer_block_height,
            canister_id: topup_canister_id
        }
    ) {
        Ok(b) => b,
        Err(candid_error) => {
            return Err(LedgerTopupCyclesCmcNotifyError::CmcNotifyTopUpQuestCandidEncodeError(format!("{}", candid_error)));
        }
    };

    let cycles: Cycles = match call_raw128(
        MAINNET_CYCLES_MINTING_CANISTER_ID,
        "notify_top_up",
        &topup_cycles_cmc_notify_call_candid,
        0
    ).await {
        Ok(candid_bytes) => match decode_one::<NotifyTopUpResult>(&candid_bytes) {
            Ok(notify_topup_result) => match notify_topup_result {
                Ok(cycles) => cycles,
                Err(cmc_notify_error) => {
                    return Err(LedgerTopupCyclesCmcNotifyError::CmcNotifyError(cmc_notify_error));
                }
            },
            Err(candid_error) => {
                return Err(LedgerTopupCyclesCmcNotifyError::CmcNotifySponseCandidDecodeError{candid_error: format!("{}", candid_error), candid_bytes: candid_bytes});
            }
        },
        Err(notify_call_error) => {
            return Err(LedgerTopupCyclesCmcNotifyError::CmcNotifyCallError((notify_call_error.0 as u32, notify_call_error.1)));
        }
    };

    Ok(cycles)
}



