package java.security;
import java.io.ByteArrayOutputStream;
/** MD5 support for Mihon source IDs, derived from the algorithm in RFC 1321. */
public class MessageDigest {
 private String algorithm="MD5";
 private final ByteArrayOutputStream input=new ByteArrayOutputStream();
 public static MessageDigest getInstance(String algorithm)throws NoSuchAlgorithmException{if(!algorithm.equalsIgnoreCase("MD5")&&!algorithm.equalsIgnoreCase("SHA-256")&&!algorithm.equalsIgnoreCase("SHA256"))throw new NoSuchAlgorithmException(algorithm);MessageDigest d=new MessageDigest();d.algorithm=algorithm;return d;}
 public void update(byte[] b){input.write(b,0,b.length);}public void update(byte[] b,int o,int n){input.write(b,o,n);}public void update(byte b){input.write(b);}public void reset(){input.reset();}public byte[] digest(){byte[] b=input.toByteArray();reset();return algorithm.equalsIgnoreCase("MD5")?md5(b):sha256(b);}public byte[] digest(byte[] b){update(b);return digest();}
 private static byte[] md5(byte[] b){int n=((b.length+8)/64+1)*64;byte[] data=new byte[n];System.arraycopy(b,0,data,0,b.length);data[b.length]=(byte)128;long bits=(long)b.length*8;for(int i=0;i<8;i++)data[n-8+i]=(byte)(bits>>>(8*i));
 int[] shift={7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21};int a0=0x67452301,b0=0xefcdab89,c0=0x98badcfe,d0=0x10325476;
 for(int off=0;off<n;off+=64){int[] w=new int[16];for(int i=0;i<16;i++)for(int j=0;j<4;j++)w[i]|=(data[off+4*i+j]&255)<<(8*j);int a=a0,c=c0,d=d0,e=b0;
 for(int i=0;i<64;i++){int f,g;if(i<16){f=(e&c)|(~e&d);g=i;}else if(i<32){f=(d&e)|(~d&c);g=(5*i+1)%16;}else if(i<48){f=e^c^d;g=(3*i+5)%16;}else{f=c^(e|~d);g=(7*i)%16;}int k=(int)(long)Math.floor(Math.abs(Math.sin(i+1))*4294967296.0);int next=e+Integer.rotateLeft(a+f+k+w[g],shift[(i/16)*4+i%4]);a=d;d=c;c=e;e=next;}a0+=a;b0+=e;c0+=c;d0+=d;}
 byte[] out=new byte[16];int[] state={a0,b0,c0,d0};for(int i=0;i<16;i++)out[i]=(byte)(state[i/4]>>>(8*(i%4)));return out;}
 private static byte[] sha256(byte[] b){
 int[] k={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
 int[] h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
 int length=((b.length+8)/64+1)*64;byte[] data=new byte[length];System.arraycopy(b,0,data,0,b.length);data[b.length]=(byte)128;long bitLength=(long)b.length*8;for(int i=0;i<8;i++)data[length-1-i]=(byte)(bitLength>>>(i*8));
 for(int off=0;off<length;off+=64){int[] w=new int[64];for(int i=0;i<16;i++)for(int j=0;j<4;j++)w[i]=(w[i]<<8)|(data[off+i*4+j]&255);for(int i=16;i<64;i++){int x=w[i-15],y=w[i-2];int s0=Integer.rotateRight(x,7)^Integer.rotateRight(x,18)^(x>>>3),s1=Integer.rotateRight(y,17)^Integer.rotateRight(y,19)^(y>>>10);w[i]=w[i-16]+s0+w[i-7]+s1;}
 int a=h[0],bb=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
 for(int i=0;i<64;i++){int s1=Integer.rotateRight(e,6)^Integer.rotateRight(e,11)^Integer.rotateRight(e,25),ch=(e&f)^(~e&g);int t1=hh+s1+ch+k[i]+w[i];int s0=Integer.rotateRight(a,2)^Integer.rotateRight(a,13)^Integer.rotateRight(a,22),maj=(a&bb)^(a&c)^(bb&c);int t2=s0+maj;hh=g;g=f;f=e;e=d+t1;d=c;c=bb;bb=a;a=t1+t2;}
 h[0]+=a;h[1]+=bb;h[2]+=c;h[3]+=d;h[4]+=e;h[5]+=f;h[6]+=g;h[7]+=hh;}
 byte[] out=new byte[32];for(int i=0;i<32;i++)out[i]=(byte)(h[i/4]>>>(24-8*(i%4)));return out;
 }
}
