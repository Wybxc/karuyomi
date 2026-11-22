package java.security;

public abstract class MessageDigestSpi {
  protected abstract void engineUpdate(byte input);

  protected abstract void engineUpdate(byte[] input, int offset, int length);

  protected abstract byte[] engineDigest();

  protected abstract void engineReset();
}
