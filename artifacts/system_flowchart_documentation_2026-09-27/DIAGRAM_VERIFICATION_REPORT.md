# ParaGO Diagram Verification Report

Reviewed: 2026-10-01

## Scope

Reviewed the dated system-flow package, the overlapping diagram package under `artifacts/diagrams_updated_2026-09-26`, its validation manifests, the flowchart generator, and the related system documentation.

The existing validation reports confirm generated geometry and schema-field loading. They do not certify semantic accuracy, live deployment state, database indexes, device behavior, or print/mobile readability.

## What passed

- The generated artifact validation reports contain no structural errors.
- The feature-flow, activity, architecture, deployment, ERD, sequence, and use-case pages report clear edge routing and fitting text in the supplied SVG checks.
- The dated package documents important current boundaries: API/database authority, terminal-first trips, explicit departure, GPS limitations, disabled-by-default group booking, and PC-only APK publication.
- The package records the known FAIRVIEW route/GPS data limitation rather than presenting it as a working booking path.

## Findings

### High priority

1. **Drawio page dimensions are wrong for tall pages.**
   - Evidence: `generate_flowcharts.js` defines the main process map at `height: 3600` and the driver page at `height: 1500`, but emits every Drawio page with `pageHeight="1250"`.
   - Impact: opening or printing the editable Drawio file can paginate, clip, or misrepresent content even when the exported SVG looks complete.
   - Improvement: emit each page's actual `width` and `height` into `mxGraphModel pageWidth/pageHeight`; regenerate the Drawio file and verify all pages in diagrams.net.

2. **Terminal transfer recovery is missing from the ride diagrams.**
   - Evidence: `docs/TERMINAL_QUEUE_RELEASE.md` states that skip/departure converts unexpired, unboarded bookings into transfer offers. The passenger and end-to-end diagrams stop at cancellation/expiry or the normal boarding path.
   - Impact: the documented recovery path is invisible, and reviewers may incorrectly conclude that an affected passenger is simply lost or cancelled.
   - Improvement: add a branch after terminal skip/departure: create transfer offer, notify passenger, accept/decline, preserve booking ID/fare/destination/original expiry, reserve the new loading jeep transactionally, and leave the offer pending when capacity is unavailable. Show that boarded passengers do not transfer.

### Medium priority

3. **The diagram corpus has no declared canonical set.**
   - Evidence: `artifacts/diagrams`, `artifacts/diagrams_updated_2026-09-26`, and `artifacts/system_flowchart_documentation_2026-09-27` contain overlapping architecture, activity, deployment, and ride-flow artifacts. Multiple READMEs describe their contents as current.
   - Impact: readers may use an older or conflicting export, and future updates can diverge.
   - Improvement: designate one canonical source package, mark the others as historical snapshots, and add a short index pointing to the canonical Drawio source and generated SVGs.

4. **Routing-provider wording is ambiguous.**
   - Evidence: `system_map.svg` labels the dependency as `OSM/routing`, while the capability documentation distinguishes OSM tiles/map rendering from the Google Routes API used for traffic-aware route previews and ETA.
   - Impact: the diagram can imply that OSM supplies the traffic-aware ETA provider.
   - Improvement: split the dependency into `OSM tiles / flutter_map` and `Google Routes API (traffic-aware routing and ETA)`, and label the Google dependency as optional/configured where appropriate.

5. **ERD and validation inventory counts disagree.**
   - Evidence: `validation-erd.json` reports 20 nodes for the all-collections page, while `validation-report.json` reports 22 for the same page. Similar differences appear for architecture, passenger activity, and sequence pages.
   - Impact: the audit trail is difficult to reproduce and weakens confidence in the validation output.
   - Improvement: define whether counts mean source nodes, visible SVG nodes, or filtered nodes; use one counting method and regenerate all manifests together. Include a generator/version and source hash in the report.

### Low priority / readability

6. **The primary process map is too tall for quick review.**
   - Evidence: `end_to_end_process_map.svg` is a 1900x3600 single sheet and the local viewer scales it responsively without detail navigation.
   - Impact: text becomes hard to read on mobile and at print scale.
   - Improvement: retain the full sheet for traceability, but add a compact overview plus linked detail sheets or zoom controls. Use print-sized exports for thesis pages.

7. **The older gallery is not mobile-friendly.**
   - Evidence: `artifacts/diagrams_updated_2026-09-26/index.html` uses a fixed 1000px layout and has no viewport declaration.
   - Impact: the gallery will require horizontal scrolling on narrow screens.
   - Improvement: add a viewport meta tag and responsive sizing; keep a minimum width only for the SVG canvas itself.

8. **Operational readiness qualifiers should be visible on diagrams.**
   - Evidence: the diagrams describe realtime, deployment, and routing behavior, while related documentation still retains staging, device, maintenance-window, and deployment gates.
   - Impact: a diagram can be read as a production guarantee rather than a current implementation snapshot.
   - Improvement: keep the dated snapshot footer and add a consistent note that live deployment, provider configuration, indexes, and device walkthroughs remain release gates.

## Recommended verification sequence

1. Fix the Drawio page dimensions in `generate_flowcharts.js` and regenerate the dated package.
2. Add the transfer-recovery branch to the passenger ride and end-to-end source pages.
3. Split OSM and Google Routes dependencies in the system map.
4. Regenerate all validation manifests with one counting definition and compare source-page counts to SVG-page counts.
5. Open every regenerated Drawio page once, then review the primary sheets at desktop, mobile, and print-size scale.
6. Mark the older overlapping folders as snapshots and update the artifact index.

## Verification conclusion

**Status: structurally generated, semantically needs revision.** The artifacts are useful and largely aligned with the current operational model, but they should not be treated as fully verified until the page-dimension, transfer-recovery, provider-label, and validation-inventory issues are corrected.