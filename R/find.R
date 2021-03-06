#' @title Search up the file system for the nearest drake cache.
#' @description Only works if the cache is a file system in a
#' hidden folder named `.drake` (default).
#' @seealso [drake_plan()], [make()],
#' @export
#' @return File path of the nearest drake cache or `NULL`
#'   if no cache is found.
#' @param path starting path for search back for the cache.
#'   Should be a subdirectory of the drake project.
#' @param directory Name of the folder containing the cache.
#' @examples
#' \dontrun{
#' test_with_dir("Quarantine side effects.", {
#' load_mtcars_example() # Get the code with drake_example("mtcars").
#' make(my_plan) # Run the project, build the target.
#' # Find the file path of the project's cache.
#' # Search up through parent directories if necessary.
#' find_cache()
#' })
#' }
find_cache <- function(
  path = getwd(),
  directory = basename(drake::default_cache_path())
) {
  while (!(directory %in% list.files(path = path, all.files = TRUE))) {
    path <- dirname(path)
    # If we can search no higher...
    if (path == dirname(path)) {
      return(NULL) # The cache does not exist
    }
  }
  file.path(path, directory)
}

#' @title Search up the file system
#'   for the nearest root path of a drake project.
#' @description Only works if the cache is a file system
#' in a folder named `.drake` (default).
#' @export
#' @seealso [drake_plan()], [make()]
#' @return File path of the nearest drake project or `NULL`
#'   if no drake project is found.
#' @param path starting path for search back for the project.
#'   Should be a subdirectory of the drake project.
#' @examples
#' \dontrun{
#' test_with_dir("Quarantine side effects.", {
#' load_mtcars_example() # Get the code with drake_example("mtcars").
#' make(my_plan) # Run the project, build the target.
#' # Find the root directory of the current drake project.
#' # Search up through parent directories if necessary.
#' find_cache()
#' })
#' }
find_project <- function(path = getwd()) {
  cache <- find_cache(path = path)
  if (is.null(cache)) {
    return(NULL)
  }
  return(dirname(cache))
}
