package prototype;
import java.util.*;
import java.util.function.*;

/** Read-only live views, including entries, ranges, iterators and default mutators. */
public final class SortedViews {
 public static <K,V> SortedMap<K,V> unmodifiableSortedMap(SortedMap<K,? extends V> map){return new ReadMap<>(map);}
 public static <E> SortedSet<E> unmodifiableSortedSet(SortedSet<E> set){return new ReadSet<>(set);}
 private static UnsupportedOperationException readOnly(){return new UnsupportedOperationException();}
 private static final class ReadMap<K,V> extends AbstractMap<K,V> implements SortedMap<K,V>{
  private final SortedMap<K,? extends V> source;private final Map<K,? extends V> view;
  ReadMap(SortedMap<K,? extends V> source){this.source=Objects.requireNonNull(source);view=Collections.unmodifiableMap(source);}
  public Comparator<? super K> comparator(){return source.comparator();}public K firstKey(){return source.firstKey();}public K lastKey(){return source.lastKey();}
  public SortedMap<K,V> subMap(K a,K b){return new ReadMap<>(source.subMap(a,b));}public SortedMap<K,V> headMap(K b){return new ReadMap<>(source.headMap(b));}public SortedMap<K,V> tailMap(K a){return new ReadMap<>(source.tailMap(a));}
  @SuppressWarnings({"unchecked","rawtypes"}) public Set<Entry<K,V>> entrySet(){return (Set)view.entrySet();}
  public Set<K> keySet(){return view.keySet();} @SuppressWarnings({"unchecked","rawtypes"}) public Collection<V> values(){return (Collection)view.values();}
  public int size(){return source.size();}public boolean containsKey(Object k){return source.containsKey(k);}public V get(Object k){return source.get(k);}
  public V put(K k,V v){throw readOnly();}public V remove(Object k){throw readOnly();}public void putAll(Map<? extends K,? extends V> m){throw readOnly();}public void clear(){throw readOnly();}
  public V putIfAbsent(K k,V v){throw readOnly();}public boolean remove(Object k,Object v){throw readOnly();}public V replace(K k,V v){throw readOnly();}public boolean replace(K k,V a,V b){throw readOnly();}
  public void replaceAll(BiFunction<? super K,? super V,? extends V> f){throw readOnly();}public V computeIfAbsent(K k,Function<? super K,? extends V> f){throw readOnly();}public V computeIfPresent(K k,BiFunction<? super K,? super V,? extends V> f){throw readOnly();}public V compute(K k,BiFunction<? super K,? super V,? extends V> f){throw readOnly();}public V merge(K k,V v,BiFunction<? super V,? super V,? extends V> f){throw readOnly();}
 }
 private static final class ReadSet<E> extends AbstractSet<E> implements SortedSet<E>{
  private final SortedSet<E> source;private final Set<E> view;
  ReadSet(SortedSet<E> source){this.source=Objects.requireNonNull(source);view=Collections.unmodifiableSet(source);}
  public Comparator<? super E> comparator(){return source.comparator();}public E first(){return source.first();}public E last(){return source.last();}
  public SortedSet<E> subSet(E a,E b){return new ReadSet<>(source.subSet(a,b));}public SortedSet<E> headSet(E b){return new ReadSet<>(source.headSet(b));}public SortedSet<E> tailSet(E a){return new ReadSet<>(source.tailSet(a));}
  public int size(){return source.size();}public boolean contains(Object e){return source.contains(e);}public Iterator<E> iterator(){return view.iterator();}
  public boolean add(E e){throw readOnly();}public boolean remove(Object e){throw readOnly();}public boolean addAll(Collection<? extends E> c){throw readOnly();}public boolean removeAll(Collection<?> c){throw readOnly();}public boolean retainAll(Collection<?> c){throw readOnly();}public boolean removeIf(Predicate<? super E> p){throw readOnly();}public void clear(){throw readOnly();}
 }
}
