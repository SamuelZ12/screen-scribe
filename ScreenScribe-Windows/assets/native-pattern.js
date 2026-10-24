'use strict';
requestAnimationFrame(()=>requestAnimationFrame(()=>{
 if(!window.screenScribe){console.error('NATIVE_TEST_BRIDGE_UNAVAILABLE');return;}
 window.screenScribe.getState().catch(()=>console.error('NATIVE_TEST_SOURCE_REJECTED'));
}));
