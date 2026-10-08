// Run inside an App Store Connect tab (session cookies). Puts build __BUILD__ in every external TestFlight group
// and submits it for beta review. Prints the build's state: WAIT (still processing), or its external beta state.
(async () => {
  const get = async u => (await fetch(u, { credentials: "include" })).json()
  const post = (u, data) => fetch(u, { method: "POST", credentials: "include",
    headers: { "Content-Type": "application/json" }, body: JSON.stringify({ data }) })
  const app = (await get("/iris/v1/apps?filter[bundleId]=com.bayujo.Ataste")).data[0].id
  const b = await get(`/iris/v1/builds?filter[app]=${app}&filter[version]=__BUILD__&include=buildBetaDetail,betaGroups`)
  const build = b.data[0]
  if (!build || build.attributes.processingState !== "VALID") return "WAIT"
  const has = new Set(build.relationships.betaGroups.data.map(g => g.id))
  for (const g of (await get(`/iris/v1/apps/${app}/betaGroups`)).data)
    if (!g.attributes.isInternalGroup && !has.has(g.id))
      await post(`/iris/v1/betaGroups/${g.id}/relationships/builds`, [{ type: "builds", id: build.id }])
  const state = b.included.find(i => i.type === "buildBetaDetails").attributes.externalBuildState
  if (state === "READY_FOR_BETA_SUBMISSION")
    await post("/iris/v1/betaAppReviewSubmissions", { type: "betaAppReviewSubmissions",
      relationships: { build: { data: { type: "builds", id: build.id } } } })
  return state
})()
