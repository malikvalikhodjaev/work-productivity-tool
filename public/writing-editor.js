export function registerDivider(Quill) {
  const BlockEmbed=Quill.import('blots/block/embed');
  class Divider extends BlockEmbed {
    static blotName='divider';
    static tagName='HR';
    static className='writing-divider';
    static value(){return true;}
  }
  Quill.register(Divider,true);
}

function dividerLine(quill,range){
  if(!range||range.length)return null;
  const [line,offset]=quill.getLine(range.index);
  if(!line)return null;
  const formats=line.formats();
  if(formats.list||formats.blockquote)return null;
  const start=quill.getIndex(line),text=quill.getText(start,line.length()-1);
  return {start,text,offset};
}

function replaceDivider(quill,start){
  const Delta=quill.constructor.import('delta');
  quill.history.cutoff();
  quill.updateContents(new Delta().retain(start).delete(3).insert({divider:true}),'user');
  quill.setSelection(start+1,0,'silent');
  quill.history.cutoff();
}

export function dividerKeyboardBinding(){
  return {key:'Enter',collapsed:true,prefix:/^---$/,suffix:/^$/,handler(range){
    const line=dividerLine(this.quill,range);
    if(!line||line.text!=='---')return true;
    replaceDivider(this.quill,line.start);return false;
  }};
}

export function enableTypedDivider(quill){
  quill.root.addEventListener('beforeinput',event=>{
    if(!quill.isEnabled()||!event.cancelable||event.isComposing||event.inputType!=='insertText'||typeof event.data!=='string')return;
    const range=quill.getSelection(),line=dividerLine(quill,range);
    if(!line||line.offset!==line.text.length||line.text+event.data!=='---')return;
    event.preventDefault();
    quill.insertText(range.index,event.data,'user');
    replaceDivider(quill,line.start);
  });
}

export const writingPlainText=document=>document.ops.map(op=>typeof op.insert==='string'?op.insert:'\n---\n').join('');
