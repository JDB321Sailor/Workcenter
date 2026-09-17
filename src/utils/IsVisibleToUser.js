/**
 * A helper function that filters all the sections or an item based on current users permissions
 * Checks each sections displayData for hideForUsers, showForUsers and hideForGuests
 * as well as the SSO group/role rules: show/hideForGroups and show/hideForRoles
 * Returns an array of sections that the current logged in user has permissions for
 */

// Import helper functions from auth, to get current user, and check if guest
import { localStorageKeys } from '@/utils/config/defaults';
import { isLoggedInAsGuest } from '@/utils/auth/Auth';

/* Helper function, checks if a given testValue is found in the visibility list */
const determineVisibility = (visibilityList, testValue) => {
  let isFound = false;
  visibilityList.forEach((visibilityItem) => {
    if (visibilityItem.toLowerCase() === testValue.toLowerCase()) isFound = true;
  });
  return isFound;
};

/* Helper function, determines if two arrays have any intersecting elements
   (one or more items that are the same) */
const determineIntersection = (source = [], target = []) => {
  const intersections = source.filter(item => target.indexOf(item) !== -1);
  return intersections.length > 0;
};

/* Returns false if the displayData of a section/item
 * says it should not be rendered for current user/guest */
export const isVisibleToUser = (displayData, currentUser, isGuest) => {
  if (isGuest === undefined) isGuest = isLoggedInAsGuest();

  // Checks if user explicitly has access to a certain section
  const checkVisibility = () => {
    if (!currentUser) return true;
    const hideForUsers = displayData.hideForUsers || [];
    const cUsername = currentUser.user.toLowerCase();
    return !determineVisibility(hideForUsers, cUsername);
  };
  // Checks if user is explicitly prevented from viewing a certain section/item
  const checkHiddenability = () => {
    if (!currentUser) return true;
    const cUsername = currentUser.user.toLowerCase();
    const showForUsers = displayData.showForUsers || [];
    if (showForUsers.length < 1) return true;
    return determineVisibility(showForUsers, cUsername);
  };
  const getUserInfo = () => {
    try { return JSON.parse(localStorage.getItem(localStorageKeys.KEYCLOAK_INFO) || '{}'); }
    catch { return {}; }
  };
  /* show/hideForKeycloakUsers are the legacy names for these rules, still silently supported */
  const pickRule = (newList, legacyList) => (
    (newList && newList.length > 0) ? newList : (legacyList || [])
  );
  const checkGroupRoleVisibility = () => {
    const legacy = displayData.hideForKeycloakUsers || {};
    const hideForGroups = pickRule(displayData.hideForGroups, legacy.groups);
    const hideForRoles = pickRule(displayData.hideForRoles, legacy.roles);
    if (hideForGroups.length < 1 && hideForRoles.length < 1) return true;

    const { groups, roles } = getUserInfo();
    return !(determineIntersection(hideForRoles, roles)
      || determineIntersection(hideForGroups, groups));
  };
  const checkGroupRoleHiddenability = () => {
    const legacy = displayData.showForKeycloakUsers;
    const showForGroups = pickRule(displayData.showForGroups, legacy && legacy.groups);
    const showForRoles = pickRule(displayData.showForRoles, legacy && legacy.roles);
    if (!legacy && showForGroups.length < 1 && showForRoles.length < 1) return true;

    const { groups, roles } = getUserInfo();
    return determineIntersection(showForRoles, roles)
      || determineIntersection(showForGroups, groups);
  };
  // Checks if the current user is a guest, and if section/item allows for guests
  const checkIfHideForGuest = () => {
    const hideForGuest = displayData.hideForGuests;
    return !(hideForGuest && isGuest);
  };
  return checkVisibility()
    && checkHiddenability()
    && checkIfHideForGuest()
    && checkGroupRoleVisibility()
    && checkGroupRoleHiddenability();
};

export default isVisibleToUser;
