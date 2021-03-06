#' Select NHDplus features via polygon or circular buffer of coordinate pair
#'
#' @export
#' @param lon numeric longitude. optional
#' @param lat numeric latitude. optional
#' @param poly sfc polygon. optional
#' @param dsn character data source
#' @param buffer_dist numeric buffer in units of coordinate degrees
#' @param approve_all_dl logical blanket approval to download all missing data
#' @examples \dontrun{
#' library(sf)
#' wk <- wikilake::lake_wiki("Gull Lake (Michigan)")
#'
#' pnt <- st_as_sf(wk, coords = c("Lon", "Lat"), crs = 4326)
#' pnt <- st_transform(pnt, st_crs(vpu_shp))
#' # nhd_plus_list(nhdR::find_vpu(pnt))
#'
#' qry <- nhd_plus_query(wk$Lon, wk$Lat,
#'          dsn = c("NHDWaterbody", "NHDFlowLine"), buffer_dist = 0.05)
#'
#' plot(qry$sp$NHDWaterbody$geometry, col = "blue")
#' plot(qry$sp$NHDFlowLine$geometry, col = "cyan", add = TRUE)
#' plot(qry$pnt, col = "red", pch = 19, add = TRUE)
#' axis(1); axis(2)
#'
#' library(ggplot2)
#' ggplot(qry$sp$NHDWaterbody) + geom_sf()
#'
#' wbd <- qry$sp$NHDWaterbody[which.max(st_area(qry$sp$NHDWaterbody)),]
#' qry_lines <- nhd_plus_query(poly = st_as_sfc(st_bbox(wbd)),
#'                             dsn = "NHDFlowLine")
#' ggplot() +
#'   geom_sf(data = qry$sp$NHDWaterbody) +
#'   geom_sf(data = qry_lines$sp$NHDFlowLine, color = "red")
#' }

nhd_plus_query <- function(lon = NA, lat = NA, poly = NA,
                           dsn, buffer_dist = 0.05, approve_all_dl = FALSE){

  if(all(!is.na(c(lon, lat, poly)))){
    stop("Must specify either lon and lat or poly but not both.")
  }

  if(all(!is.na(c(lon, lat)))){
    pnt <- sf::st_sfc(sf::st_point(c(lon, lat)))
    sf::st_crs(pnt) <- sf::st_crs(nhdR::vpu_shp)
    vpu <- find_vpu(pnt)

    sp <- lapply(dsn, function(x) nhd_plus_load(vpu = vpu, dsn = x,
                                          approve_all_dl = approve_all_dl))
    names(sp) <- dsn

    sp_sub <- select_point_overlay(pnt = pnt, sp = sp,
                                   buffer_dist = buffer_dist)

    pnt <- sf::st_transform(pnt, sf::st_crs(sp_sub[[1]]))
    list(pnt = pnt, sp = sp_sub)
  }else{

    poly <- st_transform(poly, sf::st_crs(nhdR::vpu_shp))
    vpu <- find_vpu(poly)

    sp <- lapply(dsn, function(x) nhd_plus_load(vpu = vpu, dsn = x,
                                          approve_all_dl = approve_all_dl))
    names(sp) <- dsn

    sp_sub <- select_poly_overlay(poly = poly, sp = sp)

    list(sp = sp_sub)
  }
}

#' Select NHD features clipped by a circular buffer a coordinate pair
#'
#' @export
#' @import datasets
#' @param lon numeric longitude
#' @param lat numeric latitude
#' @param dsn character data source
#' @param buffer_dist numeric buffer in units of coordinate degrees
#' @examples \dontrun{
#' wk <- wikilake::lake_wiki("Worden Pond")
#' qry <- nhd_query(wk$Lon, wk$Lat, dsn = c("NHDWaterbody", "NHDFlowline"))
#'
#' plot(sf::st_geometry(qry$sp$NHDWaterbody), col = "blue")
#' plot(sf::st_geometry(qry$sp$NHDFlowline), col = "cyan", add = TRUE)
#' plot(qry$pnt, col = "red", pch = 19, add = TRUE)
#' axis(1); axis(2)
#' }

nhd_query <- function(lon, lat, dsn, buffer_dist = 0.05){

  pnt <- sf::st_sfc(sf::st_point(c(lon, lat)))
  sf::st_crs(pnt) <- sf::st_crs(nhdR::vpu_shp)

  state <- find_state(pnt)
  state_abb <- datasets::state.abb[tolower(datasets::state.name) == state]

  sp <- lapply(dsn, function(x) nhd_load(state = state_abb, dsn = x))
  names(sp) <- dsn

  sp_sub <- select_point_overlay(pnt = pnt, sp = sp, buffer_dist = buffer_dist)

  pnt <- sf::st_transform(pnt, sf::st_crs(sp_sub[[1]]))

  list(pnt = pnt, sp = sp_sub)
}

#' Select features clipped by a point buffer around a point
#'
#' @param pnt geographic point of class sfc
#' @param sp list of sf data frames
#' @param buffer_dist numeric buffer in units of coordinate degrees
#' @export
#' @examples \dontrun{
#' wk <- wikilake::lake_wiki("Gull Lake (Michigan)")
#' pnt <- sf::st_sfc(sf::st_point(c(wk$Lon, wk$Lat)))
#' sf::st_crs(pnt) <- 4326
#' sp <- lapply(c("NHDWaterbody", "NHDFlowLine"),
#'           function(x) nhd_plus_load(vpu = 4, dsn = x))
#' names(sp) <- c("NHDWaterbody", "NHDFlowLine")
#' qry <- select_point_overlay(pnt = pnt, sp = sp, buffer_dist = 0.05)
#' plot(qry$NHDWaterbody$geometry)
#'
#'}
select_point_overlay <- function(pnt, sp, buffer_dist = 0.05){

  pnt_buff  <- sf::st_sfc(sf::st_buffer(pnt, dist = buffer_dist))
  sf::st_crs(pnt_buff) <- sf::st_crs(pnt) # <- sf::st_crs(nhdR::vpu_shp)

  utm_zone <- long2UTM(sf::st_coordinates(pnt)[1])
  crs <- paste0("+proj=utm +zone=", utm_zone, " +datum=WGS84")

  pnt      <- sf::st_transform(pnt, crs = crs)
  pnt_buff <- sf::st_transform(pnt_buff, crs = crs)

  if(all(class(sp) == "list")){
    sp    <- lapply(sp, function(x) sf::st_transform(x, crs = crs))

    sp_intersecting <- lapply(sp,
                              function(x) unlist(lapply(
                                sf::st_intersects(x, pnt_buff), length)) > 0)

    sp_sub <- lapply(seq_len(length(sp_intersecting)),
                     function(x) sp[[x]][sp_intersecting[[x]],])
    names(sp_sub) <- names(sp)
  }else{
    sp <- sf::st_transform(sp, crs = crs)
    sp_intersecting <- unlist(lapply(
                          sf::st_intersects(sp, pnt_buff), length)) > 0

    sp_sub <- sp[sp_intersecting,]
  }

  sp_sub
}

#' Select features clipped by a polygon
#'
#' @param poly sf *polygon object
#' @param sp list of sf data frames
#'
#' @importFrom sf st_crs st_coordinates st_transform st_intersects
#' @export
#'
select_poly_overlay <- function(poly, sp){

  utm_zone <- long2UTM(sf::st_coordinates(poly)[1])
  crs <- paste0("+proj=utm +zone=", utm_zone, " +datum=WGS84")

  poly      <- sf::st_transform(poly, crs = crs)

  if(all(class(sp) == "list")){
    sp    <- lapply(sp, function(x) sf::st_transform(x, crs = crs))

    sp_intersecting <- lapply(sp,
                              function(x) unlist(lapply(
                                sf::st_intersects(x, poly), length)) > 0)

    sp_sub <- lapply(seq_len(length(sp_intersecting)),
                     function(x) sp[[x]][sp_intersecting[[x]],])
    names(sp_sub) <- names(sp)
  }else{
    sp <- sf::st_transform(sp, crs = crs)
    sp_intersecting <- unlist(lapply(
      sf::st_intersects(sp, poly), length)) > 0

    sp_sub <- sp[sp_intersecting,]
  }

  sp_sub
}

#' Return terminal reaches from collection intersecting lake
#'
#' @param lon numeric decimal degree longitude
#' @param lat numeric decimal degree latitude
#' @param network sf lines collection
#' @param approve_all_dl logical blanket approval to download all missing data
#'
#' @export
#' @importFrom sf st_area st_centroid st_union
#' @importFrom rlang .data
#'
#' @examples \dontrun{
#' coords <- data.frame(lat = 20.79722, lon = -156.47833)
#' terminal_reaches(coords$lon, coords$lat)
#'
#' coords <- data.frame(lat = 41.42217, lon = -73.24189)
#' terminal_reaches(coords$lon, coords$lat)
#'
#' network <- nhd_plus_query(lon = coords$lon, lat = coords$lat,
#'                      dsn = "NHDFlowline", buffer_dist = 0.02)$sp$NHDFlowline
#' t_reach <- terminal_reaches(network = network)
#'
#' plot(network$geometry)
#' plot(t_reach$geometry, col = "red", add = TRUE)
#' }
terminal_reaches <- function(lon = NA, lat = NA, network = NA,
                             approve_all_dl = FALSE){

  if(all(is.na(network))){
    pnt <- sf::st_sfc(sf::st_point(c(lon, lat)))
    sf::st_crs(pnt) <- sf::st_crs(nhdR::vpu_shp)
    vpu <- find_vpu(pnt)

    poly <- nhd_plus_query(lon, lat, dsn = "NHDWaterbody",
                           buffer_dist = 0.01,
                           approve_all_dl = approve_all_dl)$sp$NHDWaterbody
    poly <- poly[which.max(st_area(poly)),] # find lake polygon
    network_lines <- nhd_plus_query(poly = poly,
                                  dsn = "NHDFlowline")$sp$NHDFlowline
  }else{
    network_lines <- network
    vpu <- find_vpu(st_centroid(st_union(network_lines)))
  }

  network_table <- nhd_plus_load(vpu = vpu, "NHDPlusAttributes",
                                 "PlusFlow", approve_all_dl = approve_all_dl)
  names(network_table) <- tolower(names(network_table))
  names(network_lines) <- tolower(names(network_lines))

  network_table <- dplyr::filter(network_table,
                            .data$fromcomid %in% network_lines$comid |
                            .data$tocomid %in% network_lines$comid)

  # find nodes with no downstream connections and at least one upstream conn.
  res <- dplyr::filter(network_table,
                       !(network_table$tocomid %in% network_table$fromcomid))
  up_one <- network_table[network_table$tocomid  %in% res$fromcomid,]
  res <- res[which(up_one$fromcomid != 0),]

  dplyr::filter(network_lines, .data$comid %in% res$fromcomid)
}

#' Return leaf reaches from a network or query intersecting lake
#'
#' @inheritParams terminal_reaches
#'
#' @export
#' @importFrom sf st_area st_centroid st_union
#' @importFrom rlang .data
#'
#' @examples \dontrun{
#' coords <- data.frame(lat = 20.79722, lon = -156.47833)
#' leaf_reaches(coords$lon, coords$lat)
#'
#' coords <- data.frame(lat = 41.42217, lon = -73.24189)
#' leaf_reaches(coords$lon, coords$lat)
#'
#' network <- nhd_plus_query(lon = coords$lon, lat = coords$lat,
#'                           dsn = "NHDFlowline", buffer_dist = 0.02)$sp$NHDFlowline
#' l_reach <- leaf_reaches(network = network)
#'
#' plot(network$geometry)
#' plot(l_reach$geometry, col = "red", add = TRUE)
#' }
leaf_reaches <- function(lon = NA, lat = NA, network = NA, approve_all_dl = FALSE){

  if(all(is.na(network))){
    pnt <- sf::st_sfc(sf::st_point(c(lon, lat)))
    sf::st_crs(pnt) <- sf::st_crs(nhdR::vpu_shp)
    vpu <- find_vpu(pnt)

    poly <- nhd_plus_query(lon, lat, dsn = "NHDWaterbody",
                           buffer_dist = 0.01, approve_all_dl = approve_all_dl)$sp$NHDWaterbody
    poly <- poly[which.max(st_area(poly)),] # find lake polygon
    network_lines <- nhd_plus_query(poly = poly,
                                    dsn = "NHDFlowline")$sp$NHDFlowline
  }else{
    network_lines <- network
    vpu <- find_vpu(st_centroid(st_union(network_lines)))
  }

  network_table <- nhd_plus_load(vpu = vpu, "NHDPlusAttributes",
                                 "PlusFlow", approve_all_dl = approve_all_dl)
  names(network_table) <- tolower(names(network_table))
  names(network_lines) <- tolower(names(network_lines))

  # trim to network lines
  network_table_focal <- dplyr::filter(network_table,
                                 .data$fromcomid %in% network_lines$comid |
                                   .data$tocomid %in% network_lines$comid)

  # find nodes with upstream connections but not in the focal set
  up_one <- network_table[network_table$tocomid  %in% network_table_focal$fromcomid,]
  res <- up_one[!(up_one$fromcomid %in% network_table_focal$tocomid),]

  res <- res[which(res$tocomid != 0 & res$fromcomid != 0),]

  dplyr::filter(network_lines, .data$comid %in% res$tocomid)

  # plot(network_lines$geometry)
  # plot(res$geometry, col = "red", add = TRUE)
}
