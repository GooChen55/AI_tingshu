<template>
 <view class="player">
  <image :src="track?.coverUrl||'/listen/static/logo.png'" mode="aspectFill"/>
  <text class="title">{{track?.trackTitle||'正在加载声音…'}}</text>
  <text class="time">{{current.toFixed(1)}} / {{duration.toFixed(1)}} 秒</text>
  <slider :value="current" :max="Math.max(1,duration)" :disabled="!ready||!duration" @change="seek"/>
  <view class="controls"><button :disabled="!ready" @click="toggle">{{playing?'暂停':'播放'}}</button><button class="secondary" :disabled="!store.token||!ready||saving" @click="save">保存当前进度</button></view>
  <text class="hint">{{store.token?'登录后每 10 秒自动保存，暂停和离开时也会保存。':'未登录：可以试听，登录后才能保存进度。'}}</text>
  <text class="hint">{{message}}</text><text class="error">{{error}}</text>
  <button class="secondary" @click="go('/pages/login/login')" v-if="!store.token">账号登录</button>
  <button class="secondary" @click="go('/pages/detail/detail?id='+albumId)">返回专辑</button>
  <button class="secondary" @click="openAssistant()">听见助手</button>
 </view>
</template>
<script setup lang="ts">
import {openAssistant} from "../../stores/assistant"

import {ref} from 'vue';
import {onLoad,onUnload,onHide} from '@dcloudio/uni-app';
import {listeningRequest} from '../../api/listening';
import {BASE_URL} from '../../config/confjg';
import {useUserStore} from '../../stores/user';
const store=useUserStore(),track=ref<any>(null),current=ref(0),duration=ref(0),playing=ref(false),ready=ref(false),saving=ref(false),message=ref(''),error=ref('');
let albumId=900001,trackId=900001,restore=0,restored=false,timer:any,ctx:any,disposed=false;
function go(url:string){uni.navigateTo({url})}
function toggle(){if(!ctx||!ready.value)return;if(playing.value)ctx.pause();else ctx.play()}
function seek(e:any){if(!ctx)return;ctx.seek(Number(e.detail.value));current.value=Number(e.detail.value)}
function metadata(){
 duration.value=Number(ctx.duration)||Number(track.value.mediaDuration)||0;
 if(duration.value>0&&!restored){restored=true;const start=restore<duration.value?restore:0;if(start>0)ctx.seek(start);current.value=start}
}
async function save(){
 if(!store.token||!ready.value||!track.value||saving.value)return;
 const seconds=Number(current.value.toFixed(2));saving.value=true;
 try{await listeningRequest('/api/playback/progress','POST',{albumId,trackId,breakSecond:seconds});message.value='已保存：'+seconds.toFixed(1)+' 秒'}
 catch(e:any){error.value=e.message}finally{saving.value=false}
}
onLoad(async(options:any)=>{
 try{
  trackId=Number(options.trackId||900001);track.value=await listeningRequest('/api/content/tracks/'+trackId);albumId=Number(track.value.albumId);
  if(store.token){try{const p=await listeningRequest('/api/playback/progress/'+trackId);restore=Number(p.breakSecond)||0;message.value='上次保存：'+restore.toFixed(1)+' 秒'}catch(e:any){error.value=e.message}}
  if(disposed)return;
  ctx=uni.createInnerAudioContext();ctx.autoplay=false;
  ctx.onCanplay(()=>{ready.value=true;metadata()});
  ctx.onTimeUpdate(()=>{metadata();current.value=ctx.currentTime});
  ctx.onPlay(()=>playing.value=true);
  ctx.onPause(()=>{playing.value=false;save()});
  ctx.onError(()=>{ready.value=false;playing.value=false;error.value='音频暂时无法播放，请尝试本地示例或其他声音'});
  ctx.onEnded(()=>{playing.value=false;save()});
  ctx.src=track.value.mediaUrl.startsWith('/')?BASE_URL+track.value.mediaUrl:track.value.mediaUrl;
  timer=setInterval(()=>{if(playing.value)save()},10000);
 }catch(e:any){error.value=e.message}
});
onHide(()=>{if(ctx){ctx.pause();save()}});
onUnload(()=>{disposed=true;clearInterval(timer);if(ctx){save();ctx.destroy()}});
</script>
<style scoped>.player{padding:50rpx;max-width:600px;margin:auto;background:#f3f5ef;min-height:100vh}.player image{width:320rpx;height:320rpx;display:block;margin:40rpx auto;border-radius:28rpx}.title{display:block;text-align:center;font-size:36rpx;font-weight:bold;margin:30rpx 0}.time{display:block;text-align:center;color:#567363}.controls{display:flex;gap:20rpx}button{background:#244f45;color:white;border-radius:14rpx;margin:20rpx 0}.secondary{background:#e8efe6;color:#244f45}.controls button{flex:1;font-size:26rpx}.hint{display:block;line-height:1.8;font-size:26rpx;color:#789183;margin:24rpx 0}.error{display:block;color:#a04836}.player{background:#f8f8f2;max-width:760px;padding:36px 36px 100px}.title{font-size:25px;line-height:1.6}.player image{width:240px;height:240px;box-shadow:0 18px 50px #285a4b15;border-radius:24px}.time{font-size:13px}.hint{font-size:13px;color:#87947d}.player button{font-size:13px;padding:12px 20px;line-height:1.8;border-radius:12px}.controls button{font-size:13px}.secondary{border:1px solid #dce4d3}.error{font-size:13px}@media(max-width:600px){.player{padding:24px 24px 90px}.player image{width:190px;height:190px}.title{font-size:21px}.controls{gap:10px}.controls button{font-size:12px}.hint{font-size:12px}}</style>
