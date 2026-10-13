import test from 'node:test';
import assert from 'node:assert/strict';
import {youtubeVideoUrl} from '../public/focus-youtube.js';

test('YouTube принимает обычные ссылки и не встраивает произвольные сайты, скрипты или дополнительные параметры',()=>{
  const id='M7lc1UVf-VE';
  for(const url of ['https://www.youtube.com/watch?v='+id+'&feature=shared','https://youtu.be/'+id,'https://m.youtube.com/shorts/'+id,'https://www.youtube.com/live/'+id]){const video=youtubeVideoUrl(url);assert.equal(video.id,id);assert.equal(new URL(video.embed).hostname,'www.youtube-nocookie.com');assert.equal(new URL(video.embed).searchParams.get('autoplay'),'0');assert.equal(new URL(video.embed).searchParams.get('loop'),'1');}
  for(const url of ['javascript:alert(1)','https://youtube.com.evil.test/watch?v='+id,'https://evil.test/'+id,'https://user:pass@youtube.com/watch?v='+id,'https://youtube.com:9000/watch?v='+id,'https://youtu.be/bad','https://youtube.com/playlist?list=PL123'])assert.throws(()=>youtubeVideoUrl(url));
});
