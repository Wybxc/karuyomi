/* Atomic IndexedDB storage; HTTP policy stays in the unchanged OkHttp interceptor/strategy. */
(() => {
 const namespace=new URL(location.href).searchParams.get('plugin')||'webtoons',workerId=crypto.randomUUID();
 let opening;
 const open=()=>opening||=(new Promise((resolve,reject)=>{
  const request=indexedDB.open('teavm-http-cache-v1',1);
  request.onupgradeneeded=()=>{request.result.createObjectStore('entries',{keyPath:'key'});request.result.createObjectStore('directories',{keyPath:'key'});};
  request.onsuccess=()=>{request.result.onversionchange=()=>{request.result.close();opening=null;};resolve(request.result);};request.onerror=()=>{opening=null;reject(request.error);};request.onblocked=()=>{opening=null;reject(Error('Browser cache database upgrade blocked'));};
 }));
 const decode=body=>Uint8Array.from(atob(body),c=>c.charCodeAt(0));
 function encode(bytes){let result='';for(let i=0;i<bytes.length;i+=16384)result+=String.fromCharCode(...bytes.subarray(i,i+16384));return btoa(result);}
 self.teaCache=async input=>{
  const request=JSON.parse(input),database=await open(),owner=[namespace,request.directory],key=[...owner,request.url||''];
  return JSON.stringify(await new Promise((resolve,reject)=>{
   const tx=database.transaction(['entries','directories'],'readwrite'),entries=tx.objectStore('entries'),directories=tx.objectStore('directories');let result={},failure;
   tx.oncomplete=()=>resolve(result);tx.onerror=()=>reject(failure||tx.error);tx.onabort=()=>reject(failure||tx.error||Error('Browser cache transaction aborted'));
   // All dependent IDB requests are issued from IDB callbacks, keeping the transaction live.
   const getDirectory=directories.get(owner);getDirectory.onsuccess=()=>{
    const state=getDirectory.result||{key:owner,sequence:0,generation:0};state.locks||={};
    for(const [url,lock] of Object.entries(state.locks))if(lock.expires<Date.now())delete state.locks[url];
    const cursor=entries.openCursor(IDBKeyRange.bound([...owner,''],[...owner,'\uffff'])),rows=[];
    cursor.onsuccess=()=>{const current=cursor.result;if(current){const row=current.value;if(row.key[0]===owner[0]&&row.key[1]===owner[1])rows.push(row);current.continue();return;}
     try{
      let row=rows.find(value=>value.url===request.url),size=rows.reduce((sum,value)=>sum+value.bytes,0);
      const remove=value=>{entries.delete(value.key);delete state.locks[value.url];size-=value.bytes;rows.splice(rows.indexOf(value),1);};
      const touch=value=>{value.access=++state.sequence;entries.put(value);};
      const trim=()=>{rows.sort((a,b)=>a.access-b.access);while(size>request.maxSize&&rows.length)remove(rows[0]);};
      switch(request.operation){
       case 'get':if(row){touch(row);result={entry:{metadata:row.metadata,body:encode(row.body),version:row.version,generation:state.generation}};}break;
       case 'begin':if(state.locks[request.url])result={accepted:false};else{const editor=crypto.randomUUID();state.locks[request.url]={editor,owner:workerId+'/'+request.handle,expires:Date.now()+300000};result={accepted:true,editor,version:row?.version??null,generation:state.generation};}break;
       case 'put':case 'update':{
        const lock=state.locks[request.url];
        const hasEditor=request.operation==='put'?lock?.editor===request.editor:!lock;
        const matches=hasEditor&&(row?.version??null)===(request.expected??null)&&state.generation===request.generation;
        if(request.operation==='put'&&lock?.editor===request.editor)delete state.locks[request.url];
        if(!matches||(request.operation==='update'&&!row)){result={committed:false};break;}
        const body=request.operation==='update'?row.body:decode(request.body),metadata=request.metadata;
        const bytes=body.byteLength+new TextEncoder().encode(JSON.stringify(metadata)).byteLength;
        if(row)remove(row);
        if(bytes<=request.maxSize){row={key,url:request.url,metadata,body,bytes,version:crypto.randomUUID(),access:++state.sequence};rows.push(row);size+=bytes;entries.put(row);trim();result={committed:true};}else result={committed:false};
        break;
       }
       case 'remove':if(row)remove(row);delete state.locks[request.url];break;
       case 'abort':if(state.locks[request.url]?.editor===request.editor)delete state.locks[request.url];break;
       case 'close':for(const [url,lock] of Object.entries(state.locks))if(lock.owner===workerId+'/'+request.handle)delete state.locks[url];break;
       case 'clear':for(const value of [...rows])remove(value);state.locks={};state.generation++;break;
       case 'urls':result={urls:rows.sort((a,b)=>a.access-b.access).map(value=>value.url)};break;
       case 'initialize':case 'flush':trim();break;
       case 'size':result={size};break;
       default:throw Error('Unknown browser cache operation '+request.operation);
      }
      directories.put(state);
     }catch(error){failure=error;tx.abort();}
    };
   };
  }));
 };
})();
