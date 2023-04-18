
use ic_cdk::{
    api::{
        call::{
            reply,
            arg_data
        }
    },
    export::{
        candid::{Func}
    },
    trap
};

use serde_bytes::ByteBuf;

use num_traits::cast::ToPrimitive;

mod tools;
use tools::{
    localkey::{
        refcell::{
            with
        }
    },
    make_file_certificate_header,
    create_opt_stream_callback_token,
};

mod types;
use types::{
    StreamStrategy,
    HttpRequest,
    HttpResponse,
    StreamCallbackTokenBackwards,
    StreamCallbackHttpResponse
};

mod data;
use data::{
    FILES,
};

mod upgrade;
pub use upgrade::{pre_upgrade, post_upgrade};

mod files;






// public methods

#[export_name = "canister_query see_filepaths"]
extern "C" fn canister_query_see_filepaths() {
    ic_cdk::setup();

    with(&FILES, |files| {
        reply::<(Vec<&String>,)>((files.keys().collect::<Vec<&String>>(),)); 
    });
}

#[export_name = "canister_query http_request"]
extern "C" fn http_request() {
    ic_cdk::setup();
    
    let (quest,): (HttpRequest,) = arg_data::<(HttpRequest,)>(); 
    
    let path: &str = quest.url.split("?").next().unwrap();
    
    with(&FILES, |files| {
        match files.get(path) {
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
                headers.extend(file.headers.iter().map(|tuple: &(String, String)| { (&*tuple.0, &*tuple.1) }));
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

#[export_name = "canister_query http_request_stream_callback"]
extern "C" fn http_request_stream_callback() {
    ic_cdk::setup();
    
    let (token,): (StreamCallbackTokenBackwards,) = arg_data::<(StreamCallbackTokenBackwards,)>(); 

    with(&FILES, |files| {
        match files.get(&token.key) {
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



