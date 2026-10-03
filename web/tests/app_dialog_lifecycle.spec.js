const {test,expect}=require('@playwright/test');
const path=require('node:path');

test('cancelled async validation cannot confirm a subsequently opened dialog',async({page})=>{
  await page.setContent('<button id="launch">Launch</button>');
  await page.addScriptTag({path:path.resolve(__dirname,'../js/app-dialogs.js')});
  await page.evaluate(()=>{
    window.firstResult='pending';window.secondResult='pending';
    window.appDialog.form({
      title:'First dialog',fields:[{name:'note',label:'Note'}],
      validate:()=>new Promise(resolve=>{window.finishFirstValidation=resolve;})
    }).then(result=>{window.firstResult=result;});
  });
  await page.getByRole('button',{name:'Continue',exact:true}).click();
  await expect(page.getByRole('button',{name:'Checking…',exact:true})).toBeDisabled();
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  await page.evaluate(()=>{
    window.appDialog.confirm('Confirm this different action?',{
      title:'Second dialog'
    }).then(result=>{window.secondResult=result;});
  });
  await page.evaluate(()=>window.finishFirstValidation(null));
  await expect(page.getByRole('dialog')).toContainText('Second dialog');
  expect(await page.evaluate(()=>({first:window.firstResult,second:window.secondResult})))
    .toEqual({first:null,second:'pending'});
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  expect(await page.evaluate(()=>window.secondResult)).toBeNull();
});

test('a current dialog still validates and returns its entered values',async({page})=>{
  await page.setContent('<button id="launch">Launch</button>');
  await page.addScriptTag({path:path.resolve(__dirname,'../js/app-dialogs.js')});
  await page.evaluate(()=>{
    window.dialogResult='pending';
    window.appDialog.form({title:'Current dialog',fields:[{name:'note',label:'Note'}],
      validate:async(values)=>values.note?'':'Enter a note.'
    }).then(result=>{window.dialogResult=result;});
  });
  await page.getByRole('button',{name:'Continue',exact:true}).click();
  await expect(page.locator('.sl-dialog-error')).toHaveText('Enter a note.');
  await page.getByLabel('Note',{exact:true}).fill('Confirmed note');
  await page.getByRole('button',{name:'Continue',exact:true}).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(await page.evaluate(()=>window.dialogResult)).toEqual({note:'Confirmed note'});
});
