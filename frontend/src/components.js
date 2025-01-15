/*

Copyright (c) 2018 - 2025 PhotoPrism UG. All rights reserved.

    This program is free software: you can redistribute it and/or modify
    it under Version 3 of the GNU Affero General Public License (the "AGPL"):
    <https://docs.photoprism.app/license/agpl>

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    The AGPL is supplemented by our Trademark and Brand Guidelines,
    which describe how our Brand Assets may be used:
    <https://www.photoprism.app/trademark>

Feel free to send an email to hello@photoprism.app if you have questions,
want to support our work, or just want to say hello.

Additional information can be found in our Developer Guide:
<https://docs.photoprism.app/developer-guide/>

*/

import PNotify from "component/notify.vue";
import PScroll from "component/scroll.vue";
import PNavigation from "component/navigation.vue";
import PLoadingBar from "component/loading-bar.vue";
import PViewer from "component/viewer.vue";

import PAboutFooter from "component/about/footer.vue";

import PAccountAppsDialog from "component/account/apps.vue";
import PAccountPasscodeDialog from "component/account/passcode.vue";
import PAccountPasswordDialog from "component/account/password.vue";

import PAlbumClipboard from "component/album/clipboard.vue";
import PAlbumToolbar from "component/album/toolbar.vue";
import PAlbumEditDialog from "component/album/dialog/edit.vue";
import PAlbumDeleteDialog from "component/album/dialog/delete.vue";

import PAuthHeader from "component/auth/header.vue";
import PAuthFooter from "component/auth/footer.vue";

import PUploadDialog from "component/dialog/upload.vue";
import PShareDialog from "component/dialog/share.vue";
import PWebdavDialog from "component/dialog/webdav.vue";
import PReloadDialog from "component/dialog/reload.vue";
import PSponsorDialog from "component/dialog/sponsor.vue";
import PConfirmDialog from "component/dialog/confirm.vue";

import PFileClipboard from "component/file/clipboard.vue";
import PFileDeleteDialog from "component/file/dialog/delete.vue";

import IconLivePhoto from "component/icon/live-photo.vue";
import IconSponsor from "component/icon/sponsor.vue";
import IconPrism from "component/icon/prism.vue";

import PPeopleMergeDialog from "component/people/dialog/merge.vue";
import PPeopleEditDialog from "component/people/dialog/edit.vue";

import PPhotoCards from "component/photo/view/cards.vue";
import PPhotoMosaic from "component/photo/view/mosaic.vue";
import PPhotoList from "component/photo/view/list.vue";
import PPhotoClipboard from "component/photo/clipboard.vue";
import PPhotoToolbar from "component/photo/toolbar.vue";
import PPhotoPreview from "component/photo/preview.vue";
import PPhotoArchiveDialog from "component/photo/dialog/archive.vue";
import PPhotoAlbumDialog from "component/photo/dialog/album.vue";
import PPhotoEditDialog from "component/photo/dialog/edit.vue";
import PPhotoDeleteDialog from "component/photo/dialog/delete.vue";

import PServiceAddDialog from "component/service/dialog/add.vue";
import PServiceRemoveDialog from "component/service/dialog/remove.vue";
import PServiceEditDialog from "component/service/dialog/edit.vue";
import PServiceUploadDialog from "component/service/dialog/upload.vue";

import PLabelClipboard from "component/label/clipboard.vue";
import PLabelDeleteDialog from "component/label/dialog/delete.vue";
import PLabelEditDialog from "component/label/dialog/edit.vue";

import PSubjectClipboard from "component/subject/clipboard.vue";

// Installs the components imported above.
export function install(app) {
  app.component("PNotify", PNotify);
  app.component("PScroll", PScroll);
  app.component("PNavigation", PNavigation);
  app.component("PLoadingBar", PLoadingBar);
  app.component("PViewer", PViewer);

  app.component("PAboutFooter", PAboutFooter);

  app.component("PAccountAppsDialog", PAccountAppsDialog);
  app.component("PAccountPasscodeDialog", PAccountPasscodeDialog);
  app.component("PAccountPasswordDialog", PAccountPasswordDialog);

  app.component("PAlbumClipboard", PAlbumClipboard);
  app.component("PAlbumToolbar", PAlbumToolbar);
  app.component("PAlbumEditDialog", PAlbumEditDialog);
  app.component("PAlbumDeleteDialog", PAlbumDeleteDialog);

  app.component("PAuthHeader", PAuthHeader);
  app.component("PAuthFooter", PAuthFooter);

  app.component("PUploadDialog", PUploadDialog);
  app.component("PShareDialog", PShareDialog);
  app.component("PWebdavDialog", PWebdavDialog);
  app.component("PReloadDialog", PReloadDialog);
  app.component("PSponsorDialog", PSponsorDialog);
  app.component("PConfirmDialog", PConfirmDialog);

  app.component("PFileClipboard", PFileClipboard);
  app.component("PFileDeleteDialog", PFileDeleteDialog);

  app.component("IconLivePhoto", IconLivePhoto);
  app.component("IconSponsor", IconSponsor);
  app.component("IconPrism", IconPrism);

  app.component("PLabelClipboard", PLabelClipboard);
  app.component("PLabelDeleteDialog", PLabelDeleteDialog);
  app.component("PLabelEditDialog", PLabelEditDialog);

  app.component("PPeopleMergeDialog", PPeopleMergeDialog);
  app.component("PPeopleEditDialog", PPeopleEditDialog);

  app.component("PPhotoCards", PPhotoCards);
  app.component("PPhotoMosaic", PPhotoMosaic);
  app.component("PPhotoList", PPhotoList);
  app.component("PPhotoClipboard", PPhotoClipboard);
  app.component("PPhotoToolbar", PPhotoToolbar);
  app.component("PPhotoPreview", PPhotoPreview);
  app.component("PPhotoArchiveDialog", PPhotoArchiveDialog);
  app.component("PPhotoAlbumDialog", PPhotoAlbumDialog);
  app.component("PPhotoEditDialog", PPhotoEditDialog);
  app.component("PPhotoDeleteDialog", PPhotoDeleteDialog);

  app.component("PServiceAddDialog", PServiceAddDialog);
  app.component("PServiceRemoveDialog", PServiceRemoveDialog);
  app.component("PServiceEditDialog", PServiceEditDialog);
  app.component("PServiceUploadDialog", PServiceUploadDialog);

  app.component("PSubjectClipboard", PSubjectClipboard);
}

// Default settings for standard components.
export const defaults = {
  VBtn: {
    flat: true,
    variant: "flat",
    ripple: true,
  },
  VSwitch: {
    flat: true,
    density: "compact",
    baseColor: "switch",
    color: "surface-variant",
    hideDetails: "auto",
    minWidth: 32,
    variant: "flat",
    falseValue: false,
    ripple: false,
  },
  VRating: {
    density: "compact",
    color: "on-surface",
    activeColor: "surface-variant",
    ripple: false,
  },
  VCheckbox: {
    density: "compact",
    color: "surface-variant",
    hideDetails: "auto",
    ripple: false,
  },
  VTextField: {
    flat: true,
    variant: "solo-filled",
    color: "surface-variant",
    hideDetails: "auto",
  },
  VTextarea: {
    flat: true,
    variant: "solo-filled",
    color: "surface-variant",
    hideDetails: "auto",
  },
  VOtpInput: {
    variant: "outlined",
    baseColor: "on-surface-variant",
    autofocus: true,
  },
  VAutocomplete: {
    flat: true,
    variant: "solo-filled",
    color: "surface-variant",
    itemTitle: "text",
    itemValue: "value",
    hideDetails: "auto",
    hideNoData: true,
  },
  VCombobox: {
    flat: true,
    variant: "solo-filled",
    color: "surface-variant",
    itemTitle: "text",
    itemValue: "value",
    hideDetails: "auto",
  },
  VSelect: {
    flat: true,
    variant: "solo-filled",
    color: "surface-variant",
    itemTitle: "text",
    itemValue: "value",
    hideDetails: "auto",
  },
  VCard: {
    density: "compact",
    color: "background",
    flat: true,
    ripple: false,
  },
  VTab: {
    color: "on-surface",
    baseColor: "on-surface-variant",
    ripple: false,
  },
  VTabs: {
    grow: true,
    elevation: 0,
    color: "on-surface",
    bgColor: "secondary",
    baseColor: "secondary",
    sliderColor: "surface-variant",
  },
  VTable: {
    density: "comfortable",
  },
  VListItem: {
    ripple: false,
  },
  VDataTable: {
    color: "background",
    itemsPerPage: -1,
    hover: true,
  },
  VExpansionPanel: {
    tile: true,
    ripple: false,
  },
  VExpansionPanels: {
    flat: true,
    tile: true,
    static: true,
    variant: "accordion",
    bgColor: "secondary-light",
    ripple: false,
  },
  VProgressLinear: {
    height: 10,
    rounded: true,
    color: "surface-variant",
  },
};

// Additional icons for use with Vuetify.
export const icons = {
  live_photo: {
    component: IconLivePhoto,
    props: {
      name: "live_photo",
    },
  },
  sponsor: {
    component: IconSponsor,
    props: {
      name: "sponsor",
    },
  },
  prism: {
    component: IconPrism,
    props: {
      name: "prism",
    },
  },
};
