




#[derive(CandidType, Deserialize)]
pub struct FileServerData<CanisterData: CandidType + Deserialize> {
    pub files: Files,
    pub files_hashes: Vec<(String, [u8; 32])>,      // field is only use for the upgrades.
    pub canister_data: Option<CanisterData>,        // field is only use for the upgrades.
}
impl FileServerData {
    fn new() -> Self {
        Self {
            files: Files::new(),
            files_hashes: Vec::new(), // field is only use for the upgrades.
            canister_data: None
        }
    }
}




thread_local! {
    pub static FILE_SERVER_DATA: RefCell<FileServerData> = RefCell::new(FileServerData::new());
    
    // not save through upgrades
    pub static FILES_HASHES: RefCell<FilesHashes> = RefCell::new(FilesHashes::new()); // save through the upgrades by the files_hashes field on the FileServerData struct

}


