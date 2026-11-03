package javax.crypto.spec;import java.util.*;
public class IvParameterSpec implements java.security.spec.AlgorithmParameterSpec{
 private final byte[] iv;public IvParameterSpec(byte[] iv){this(iv,0,iv.length);}public IvParameterSpec(byte[] iv,int offset,int len){Objects.checkFromIndexSize(offset,len,iv.length);this.iv=Arrays.copyOfRange(iv,offset,offset+len);}public byte[] getIV(){return iv.clone();}}
