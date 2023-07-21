# file-server-canister

The File-Server-Canister 

Live here: https://z7kqr-4yaaa-aaaaj-qaa5q-cai.icp0.io

Key Features:
 - Users can create one or many of their own file servers.
 - Each File Server is it’s own canister.
 - Sync the file tree of a server with a local folder and serve it live on the blockchain.
 - Files are certified using certified queries.
 - Browse the files and directories of the servers.
 - Click and share the link of a server to serve an html/website file tree.
 - Create and manage your servers in a simple UI.


 ------------------------
 
 ## Build
 
 ### Build flutter frontend - must have Flutter installed.
 $ `cd frontcode && bash flutter_build`
 
 ### Build canisters: main-canister and user-canister.
 $ `cd backcode && cargo build --target wasm32-unknown-unknown --release`
 
