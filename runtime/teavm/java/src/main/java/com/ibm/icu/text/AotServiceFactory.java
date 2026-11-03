package com.ibm.icu.text;

/** Invoke original ICU constructors for its two statically known service shims. */
public final class AotServiceFactory {
  public static Object newInstance(Class<?> type)
      throws InstantiationException, IllegalAccessException {
    if (type == CollatorServiceShim.class) return new CollatorServiceShim();
    if (type == BreakIteratorFactory.class) return new BreakIteratorFactory();
    return type.newInstance();
  }
}
