package uy.kohesive.injekt.api;
public abstract class FullTypeReference<T> implements TypeReference<T>{public java.lang.reflect.Type getType(){return prototype.TypeMap.resolve(getClass().getName());}}