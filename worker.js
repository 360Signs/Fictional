importScripts('core.js');
let ranked=[];
self.onmessage=({data:d})=>{
 if(d.type==='data'){ranked=Arena.rank(Arena.stats(d.fighters,d.battles));postMessage({type:'ready',total:ranked.length,verses:[...new Set(ranked.map(f=>f.verse))].sort(),battles:d.battles.filter(b=>!b.voided).length,top:ranked.slice(0,3)});}
 if(d.type==='query'){let rows=ranked.filter(f=>(!d.q||(f.name+' '+f.verse).toLowerCase().includes(d.q.toLowerCase()))&&(!d.verse||f.verse===d.verse)&&(!d.played||f.played>0));if(d.sort==='name')rows.sort((a,b)=>a.name.localeCompare(b.name));if(d.sort==='wins')rows.sort((a,b)=>b.wins-a.wins||a.rank-b.rank);if(d.sort==='rate')rows.sort((a,b)=>b.rate-a.rate||b.played-a.played||a.rank-b.rank);if(d.sort==='low')rows.reverse();postMessage({type:'results',seq:d.seq,count:rows.length,page:d.page,rows:rows.slice(d.page*50,(d.page+1)*50)});}
 if(d.type==='lookup')postMessage({type:'lookup',key:d.key,q:d.q,rows:ranked.filter(f=>(f.name+' '+f.verse).toLowerCase().includes(d.q.toLowerCase())).slice(0,12)});
 if(d.type==='profile')postMessage({type:'profile',fighter:ranked.find(f=>f.id===d.id)});
};