import { deleteIncidentHandler } from "./handler.ts";
Deno.serve((request) => deleteIncidentHandler(request));
