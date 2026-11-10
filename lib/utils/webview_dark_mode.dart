const _darkCss = "html{filter:invert(1) hue-rotate(180deg)!important}"
    "img,video,picture,canvas,svg,[style*=background-image]{filter:invert(1) hue-rotate(180deg)!important}";

/// Makes HTW web pages match the app's dark theme. Safe to run repeatedly.
///
/// Pages that are light-only (LSF) get a colour-inverting stylesheet. Pages
/// that already render dark by themselves (the web mail follows the system
/// dark mode) are left alone — inverting those would turn them light again.
/// The decision is re-evaluated as the page loads and whenever it toggles its
/// own theme class.
///
/// The sheet is attached as a constructed stylesheet, which is not subject to
/// a page's Content-Security-Policy; a `<style>` element is the fallback.
///
/// Note: this is a normal (non-raw) Dart string, so the script must not
/// contain backslashes or dollar signs.
const String webViewDarkModeJs = """
(function(){
  if(window.__uniweDark){window.__uniweDark.on();return;}
  var css='$_darkCss';
  var sheet=null,styleEl=null,active=true;
  function attach(){
    try{
      sheet=new CSSStyleSheet();
      sheet.replaceSync(css);
      var all=[];
      for(var i=0;i<document.adoptedStyleSheets.length;i++){all.push(document.adoptedStyleSheets[i]);}
      all.push(sheet);
      document.adoptedStyleSheets=all;
    }catch(e){
      sheet=null;
      if(document.head){
        styleEl=document.createElement('style');
        styleEl.id='_ud';
        styleEl.textContent=css;
        document.head.appendChild(styleEl);
      }
    }
  }
  function setEnabled(on){
    if(sheet){sheet.disabled=!on;}
    if(styleEl){styleEl.disabled=!on;}
  }
  function pageIsDark(){
    setEnabled(false);
    try{
      var els=[document.body,document.documentElement];
      for(var i=0;i<els.length;i++){
        if(!els[i]){continue;}
        var m=getComputedStyle(els[i]).backgroundColor.match(/[0-9.]+/g);
        if(m&&m.length>=3&&(m.length<4||parseFloat(m[3])>0.5)){
          return (0.2126*m[0]+0.7152*m[1]+0.0722*m[2])<110;
        }
      }
    }catch(e){}
    return false;
  }
  function update(){
    if(!active){setEnabled(false);return;}
    if(!sheet&&!styleEl){attach();}
    setEnabled(!pageIsDark());
  }
  window.__uniweDark={
    on:function(){active=true;update();},
    off:function(){active=false;update();}
  };
  update();
  document.addEventListener('DOMContentLoaded',update);
  window.addEventListener('load',update);
  try{
    new MutationObserver(update).observe(document.documentElement,{attributes:true,attributeFilter:['class','style']});
  }catch(e){}
})();
""";

/// Turns off what [webViewDarkModeJs] did.
const String webViewLightModeJs = """
(function(){if(window.__uniweDark){window.__uniweDark.off();}})();
""";

/// Mobile user agent for Moodle, used both for signing in and by the web
/// view. Keeping it fixed makes Moodle see one consistent device, instead of
/// a "new device" on every sign-in.
const String mobileUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// Desktop user agent: LSF serves its full layout only to desktop browsers.
const String desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
