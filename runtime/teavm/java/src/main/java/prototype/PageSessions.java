package prototype;

import eu.kanade.tachiyomi.source.Source;
import eu.kanade.tachiyomi.source.model.Page;
import java.util.*;

/** Bounded, generation-local ownership of the exact Page instances returned by a Source. */
public final class PageSessions {
  public static final int MAX_SESSIONS = 2;
  public static final int MAX_PAGES = 2048;
  public static final int MAX_DTO_BYTES = 2 * 1024 * 1024;
  private final Map<String, Session> sessions = new LinkedHashMap<>();

  public static final class Session {
    public final String id;
    public final List<Page> pages;
    private final Source owner;
    private final String sourceId;
    private boolean closed;
    private int leases;

    private Session(Source owner, List<Page> pages) {
      this.id = UUID.randomUUID().toString();
      this.owner = owner;
      this.sourceId = Long.toString(owner.getId());
      this.pages = new ArrayList<>(pages);
    }
  }

  public final class Lease implements AutoCloseable {
    private final Session session;
    private final Page page;
    private boolean released;

    private Lease(Session session, Page page) {
      this.session = session;
      this.page = page;
    }

    public Page page() {
      if (released) throw new IllegalStateException("Page lease is closed");
      return page;
    }

    @Override
    public void close() {
      synchronized (PageSessions.this) {
        if (released) return;
        released = true;
        session.leases--;
        collect(session);
      }
    }
  }

  public synchronized Session open(Source owner, List<Page> pages) {
    Objects.requireNonNull(owner, "Source is required");
    Objects.requireNonNull(pages, "Page list is required");
    if (pages.size() > MAX_PAGES)
      throw new IllegalArgumentException("Page session exceeds 2048 pages");
    if (sessions.size() >= MAX_SESSIONS)
      throw new IllegalStateException("Close an existing page session before opening another");
    for (Page page : pages) Objects.requireNonNull(page, "Source returned a null Page");
    Session session = new Session(owner, pages);
    sessions.put(session.id, session);
    return session;
  }

  public synchronized Lease acquire(Source owner, String sourceId, String id, String pageKey) {
    Session session = sessions.get(id);
    if (session == null || session.closed)
      throw new IllegalArgumentException("Page session is closed or expired");
    if (session.owner != owner || !session.sourceId.equals(sourceId))
      throw new IllegalArgumentException("Page session belongs to a different Source");
    if (pageKey == null || !pageKey.matches("p-(0|[1-9][0-9]{0,3})"))
      throw new IllegalArgumentException("Invalid page key");
    int index = Integer.parseInt(pageKey.substring(2));
    if (index >= session.pages.size()) throw new IllegalArgumentException("Unknown page key");
    session.leases++;
    return new Lease(session, session.pages.get(index));
  }

  public synchronized void close(String id) {
    Session session = sessions.get(id);
    if (session == null) return;
    session.closed = true;
    collect(session);
  }

  public synchronized void clear() {
    for (Session session : new ArrayList<>(sessions.values())) {
      session.closed = true;
      collect(session);
    }
  }

  private void collect(Session session) {
    if (!session.closed || session.leases != 0) return;
    sessions.remove(session.id);
    session.pages.clear();
  }
}
