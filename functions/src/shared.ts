/**
 * Notifications for the shared planning features. The app writes calendar
 * events, to-dos and wishes directly (rules-checked); these triggers tell
 * the other person when something lands for them.
 */
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {DocumentData} from "firebase-admin/firestore";
import {db, REGION, PairDoc, getUser, firstName, notify, safeTz, logger} from "./common";

/** The other member of [pairId], or "" if the pair isn't active. */
async function partnerOf(pairId: string, uid: string): Promise<string> {
  const pair = (await db.doc(`pairs/${pairId}`).get()).data() as PairDoc | undefined;
  if (!pair || pair.status !== "active") return "";
  return pair.memberIds.find((m) => m !== uid) ?? "";
}

function clip(s: unknown, max: number): string {
  const t = String(s ?? "");
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

/** "Sam added “Dinner at Luigi's” to your calendar 📅". */
export const onEventCreated = onDocumentCreated(
  {document: "pairs/{pairId}/countdowns/{eventId}", region: REGION},
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    const pairId = event.params.pairId;
    const author = String(d.createdBy ?? "");
    const to = await partnerOf(pairId, author);
    if (!to) return;
    try {
      const [user, receiver] = await Promise.all([getUser(author), getUser(to)]);
      const date = d.date?.toDate?.() as Date | undefined;
      const when = date ?
        new Intl.DateTimeFormat("en-GB", {
          weekday: "short",
          day: "numeric",
          month: "short",
          timeZone: safeTz(receiver.timezone),
        }).format(date) :
        "";
      const isDate = d.category === "date";
      await notify(to, {
        channel: "countdowns",
        type: isDate ? "date_planned" : "event_added",
        title: isDate ?
          `${firstName(user)} planned a date 💑` :
          `${firstName(user)} added something to your calendar 📅`,
        body: `${d.emoji ?? "📅"} ${clip(d.title, 60)}${when ? ` · ${when}` : ""}`,
        data: {route: isDate ? "/dates" : "/calendar", pairId, eventId: event.params.eventId},
        prefKey: "reminders",
        user: receiver,
      });
    } catch (e) {
      logger.warn("onEventCreated notify failed", {pairId, e});
    }
  },
);

/** A task assigned to the partner (or to both) tells them. */
export const onTodoCreated = onDocumentCreated(
  {document: "pairs/{pairId}/todos/{todoId}", region: REGION},
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    const pairId = event.params.pairId;
    const author = String(d.createdBy ?? "");
    const to = await partnerOf(pairId, author);
    if (!to || (d.assignee !== null && d.assignee !== to)) return;
    const user = await getUser(author);
    await notify(to, {
      channel: "countdowns",
      type: "todo_assigned",
      title: d.assignee === to ? `${firstName(user)} gave you a task ✅` : `${firstName(user)} added a task for you both`,
      body: clip(d.text, 100),
      data: {route: "/todos", pairId, todoId: event.params.todoId},
      prefKey: "reminders",
    });
  },
);

/** "Sam finished “Book the restaurant” ✓" — to whoever created the task. */
export const onTodoUpdated = onDocumentUpdated(
  {document: "pairs/{pairId}/todos/{todoId}", region: REGION},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.doneAt || !after.doneAt) return;
    const doneBy = String(after.doneBy ?? "");
    const creator = String(after.createdBy ?? "");
    if (!doneBy || !creator || doneBy === creator) return;
    const user = await getUser(doneBy);
    await notify(creator, {
      channel: "countdowns",
      type: "todo_done",
      title: `${firstName(user)} finished a task ✓`,
      body: clip(after.text, 100),
      data: {route: "/todos", pairId: event.params.pairId, todoId: event.params.todoId},
      prefKey: "reminders",
    });
  },
);

/** New shared wish (date idea, trip…). Gift wishes stay quiet on purpose. */
export const onWishCreated = onDocumentCreated(
  {document: "pairs/{pairId}/wishes/{wishId}", region: REGION},
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d || d.category === "gift") return;
    const pairId = event.params.pairId;
    const author = String(d.createdBy ?? "");
    const to = await partnerOf(pairId, author);
    if (!to) return;
    const user = await getUser(author);
    await notify(to, {
      channel: "countdowns",
      type: "wish_added",
      title: `${firstName(user)} added to your wishlist 🌠`,
      body: clip(d.title, 100),
      data: {route: "/wishlist", pairId, wishId: event.params.wishId},
      prefKey: "reminders",
    });
  },
);
