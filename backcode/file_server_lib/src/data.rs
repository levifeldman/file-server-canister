
use std::cell::{RefCell};

use crate::{
    types::{
        Files,
        FilesHashes
    }
};



thread_local! {
    pub static FILES: RefCell<Files> = RefCell::new(Files::new());
    
    // not save through upgrades
    pub static FILES_HASHES: RefCell<FilesHashes> = RefCell::new(FilesHashes::new()); // save through the upgrades by the files_hashes field on the FileServerData struct

}


