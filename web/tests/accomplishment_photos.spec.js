const {test,expect}=require('@playwright/test');
test('filed photo reports open full size; expired or failed access can be retried',async({page})=>{
 await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`
 window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};
 window.photoCalls=[];window.photoFailure=false;
 window.appSupabase={storage:{from:bucket=>({createSignedUrl:async(path,seconds)=>{
   photoCalls.push({bucket,path,seconds});return photoFailure?{error:{message:'Unavailable'}}:{data:{signedUrl:'https://uqtupmpofjqrnefgrexm.supabase.co/storage/v1/object/sign/accomplishment-photos/guard/report.jpg?token=test'}};
 }})}};
 `}));
 await page.route('**/storage/v1/object/sign/accomplishment-photos/**',route=>route.fulfill({contentType:process.env.TEST_REPORT_PHOTO?'image/jpeg':'image/png',body:process.env.TEST_REPORT_PHOTO?require('node:fs').readFileSync(process.env.TEST_REPORT_PHOTO):Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jvXkAAAAASUVORK5CYII=','base64')}));
 await page.goto('/admin/users.html');
 await page.evaluate(async()=>{
  document.getElementById('loadingScreen').style.display='none';
  window.reportFixture={id:'report-test',summary:'Patrol completed',detailed_narrative:'Checked all posts.',review_status:'submitted',photo_path:'guard/report.jpg'};
  const list=document.getElementById('accomplishmentRecordsList');
  list.innerHTML=renderAccomplishmentReport(reportFixture);
  new bootstrap.Modal(document.getElementById('accomplishmentModal')).show();
  await loadAccomplishmentPhotos(list,[reportFixture]);
 });
 await expect(page.getByAltText('Accomplishment photo report')).toBeVisible();
 await expect(page.getByRole('link',{name:'Open photo report at full size'})).toHaveAttribute('target','_blank');
 await expect(page.locator('#accomplishmentRecordsList')).toContainText('Checked all posts.');
 expect(await page.evaluate(()=>photoCalls[0])).toEqual({bucket:'accomplishment-photos',path:'guard/report.jpg',seconds:900});
 await page.evaluate(async()=>{photoFailure=true;await loadAccomplishmentPhotos(document.getElementById('accomplishmentRecordsList'),[reportFixture]);});
 await expect(page.getByRole('button',{name:'Retry photo'})).toBeVisible();
 await page.evaluate(()=>{photoFailure=false;});
 await page.getByRole('button',{name:'Retry photo'}).click();
 await expect(page.getByAltText('Accomplishment photo report')).toBeVisible();
 await page.screenshot({path:test.info().outputPath('accomplishment-photo-report.png'),fullPage:true});
});
