package java.util.concurrent;

import java.util.*;

/** Cooperative-worker queue. Nodes stay valid for weakly consistent iterators. */
public class ConcurrentLinkedQueue<E> extends AbstractQueue<E> implements java.io.Serializable {
  private static final class Node<E> {
    E value;
    Node<E> next;

    Node(E value) {
      this.value = value;
    }
  }

  private Node<E> head = new Node<>(null), tail = head;

  public ConcurrentLinkedQueue() {}

  public ConcurrentLinkedQueue(Collection<? extends E> source) {
    addAll(source);
  }

  public synchronized boolean offer(E value) {
    Node<E> node = new Node<>(Objects.requireNonNull(value));
    tail.next = node;
    tail = node;
    return true;
  }

  public synchronized E poll() {
    for (Node<E> n = head.next; n != null; n = n.next) {
      head = n;
      if (n.value != null) {
        E value = n.value;
        n.value = null;
        return value;
      }
    }
    return null;
  }

  public synchronized E peek() {
    for (Node<E> n = head.next; n != null; n = n.next) if (n.value != null) return n.value;
    return null;
  }

  public synchronized int size() {
    int size = 0;
    for (Node<E> n = head.next; n != null; n = n.next)
      if (n.value != null && ++size == Integer.MAX_VALUE) break;
    return size;
  }

  public synchronized boolean contains(Object value) {
    if (value == null) return false;
    for (Node<E> n = head.next; n != null; n = n.next) if (value.equals(n.value)) return true;
    return false;
  }

  public synchronized boolean remove(Object value) {
    if (value == null) return false;
    for (Node<E> n = head.next; n != null; n = n.next)
      if (value.equals(n.value)) {
        n.value = null;
        return true;
      }
    return false;
  }

  public boolean addAll(Collection<? extends E> source) {
    Objects.requireNonNull(source);
    if (source == this) throw new IllegalArgumentException();
    List<E> checked = new ArrayList<>();
    for (E value : source) checked.add(Objects.requireNonNull(value));
    synchronized (this) {
      for (E value : checked) offer(value);
    }
    return !checked.isEmpty();
  }

  public synchronized void clear() {
    for (Node<E> n = head.next; n != null; n = n.next) n.value = null;
    head = tail;
  }

  public Iterator<E> iterator() {
    return new Iterator<>() {
      Node<E> cursor = head, nextNode, last;
      E nextValue;

      {
        advance();
      }

      private void advance() {
        synchronized (ConcurrentLinkedQueue.this) {
          nextNode = null;
          nextValue = null;
          while (cursor.next != null) {
            cursor = cursor.next;
            if (cursor.value != null) {
              nextNode = cursor;
              nextValue = cursor.value;
              return;
            }
          }
        }
      }

      public boolean hasNext() {
        return nextNode != null;
      }

      public E next() {
        if (nextNode == null) throw new NoSuchElementException();
        E value = nextValue;
        last = nextNode;
        advance();
        return value;
      }

      public void remove() {
        if (last == null) throw new IllegalStateException();
        synchronized (ConcurrentLinkedQueue.this) {
          last.value = null;
        }
        last = null;
      }
    };
  }
}
