import { LightningElement, api, wire } from 'lwc';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils';
import getOffers from '@salesforce/apex/OfferController.getOffers';
import canApprove from '@salesforce/apex/OfferController.canApprove';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';

export const APPROVAL_THRESHOLD = 10;

const CLOSED_PROPERTY_STATUSES = ['Under Agreement', 'Closed'];
const OPEN_OFFER_STATUSES = ['Submitted', 'Needs Approval', 'Approved'];
const BADGE_CLASSES = {
    Submitted: 'slds-badge slds-badge_lightest',
    'Needs Approval': 'slds-badge slds-theme_warning',
    Approved: 'slds-badge slds-theme_info',
    Accepted: 'slds-badge slds-theme_success',
    Rejected: 'slds-badge slds-theme_error'
};

/**
 * Same rounding as OfferService.percentBelowAsking: one decimal place, half away from zero.
 */
export function percentBelowAsking(askingPrice, amount) {
    if (!askingPrice || askingPrice <= 0 || !amount) {
        return null;
    }
    const raw = ((askingPrice - amount) / askingPrice) * 100;
    const rounded = Math.round(Math.abs(raw) * 10 + 1e-9) / 10;
    return raw < 0 ? -rounded : rounded;
}

export default class PropertyOffers extends LightningElement {
    @api recordId;

    buyerName = '';
    amount;
    isWorking = false;

    offers = [];
    offersError;
    wiredOffersResult;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    property;

    @wire(canApprove)
    approvalRight;

    @wire(getOffers, { propertyId: '$recordId' })
    wiredOffers(result) {
        this.wiredOffersResult = result;
        if (result.data) {
            this.offers = result.data;
            this.offersError = undefined;
        } else if (result.error) {
            this.offers = [];
            this.offersError = result.error;
        }
    }

    get askingPrice() {
        return getFieldValue(this.property.data, PRICE_FIELD);
    }

    get propertyStatus() {
        return getFieldValue(this.property.data, STATUS_FIELD);
    }

    get isClosedToOffers() {
        return CLOSED_PROPERTY_STATUSES.includes(this.propertyStatus);
    }

    get closedMessage() {
        return `This property is ${this.propertyStatus} and is not taking new offers.`;
    }

    get cardTitle() {
        return `Offers (${this.offers.length})`;
    }

    get hasOffers() {
        return this.offers.length > 0;
    }

    get canUserApprove() {
        return this.approvalRight?.data === true;
    }

    get previewPercent() {
        return percentBelowAsking(this.askingPrice, Number(this.amount));
    }

    get hasPreview() {
        return this.previewPercent !== null && Number(this.amount) > 0;
    }

    get previewNeedsApproval() {
        return this.hasPreview && this.previewPercent > APPROVAL_THRESHOLD;
    }

    get previewText() {
        const percent = this.previewPercent;
        if (percent > APPROVAL_THRESHOLD) {
            return `${percent.toFixed(1)}% below asking, needs broker approval`;
        }
        if (percent > 0) {
            return `${percent.toFixed(1)}% below asking`;
        }
        if (percent < 0) {
            return `${Math.abs(percent).toFixed(1)}% above asking`;
        }
        return 'At asking price';
    }

    get previewClass() {
        return this.previewNeedsApproval
            ? 'preview slds-text-color_error'
            : 'preview slds-text-color_weak';
    }

    get submitDisabled() {
        return (
            this.isWorking ||
            this.isClosedToOffers ||
            !this.buyerName.trim() ||
            !(Number(this.amount) > 0)
        );
    }

    get offerRows() {
        const propertyOpen = !this.isClosedToOffers;
        return this.offers.map((offer) => {
            const isOpen = OPEN_OFFER_STATUSES.includes(offer.Status__c);
            return {
                ...offer,
                badgeClass: BADGE_CLASSES[offer.Status__c] || 'slds-badge',
                percentLabel: this.percentLabel(offer.Percent_Below_Asking__c),
                showApprove:
                    this.canUserApprove && offer.Status__c === 'Needs Approval',
                showAccept:
                    propertyOpen &&
                    (offer.Status__c === 'Submitted' ||
                        offer.Status__c === 'Approved'),
                showReject: isOpen,
                awaitingApproval:
                    !this.canUserApprove && offer.Status__c === 'Needs Approval'
            };
        });
    }

    get errorMessages() {
        return this.offersError ? reduceErrors(this.offersError) : [];
    }

    percentLabel(percent) {
        if (percent === null || percent === undefined) {
            return '';
        }
        return percent >= 0
            ? `${Number(percent).toFixed(1)}% below asking`
            : `${Math.abs(percent).toFixed(1)}% above asking`;
    }

    handleBuyerChange(event) {
        this.buyerName = event.target.value || '';
    }

    handleAmountChange(event) {
        this.amount = event.target.value;
    }

    async handleSubmit() {
        const needsApproval = this.previewNeedsApproval;
        const buyer = this.buyerName.trim();
        await this.runAction(
            () =>
                submitOffer({
                    propertyId: this.recordId,
                    buyerName: buyer,
                    amount: Number(this.amount)
                }),
            needsApproval
                ? `Offer from ${buyer} submitted. It needs broker approval.`
                : `Offer from ${buyer} submitted.`,
            { resetForm: true }
        );
    }

    handleApprove(event) {
        return this.runAction(
            () => approveOffer({ offerId: event.target.dataset.id }),
            'Offer approved.'
        );
    }

    handleAccept(event) {
        return this.runAction(
            () => acceptOffer({ offerId: event.target.dataset.id }),
            'Offer accepted. The property is now Under Agreement.',
            { propertyChanged: true }
        );
    }

    handleReject(event) {
        return this.runAction(
            () => rejectOffer({ offerId: event.target.dataset.id }),
            'Offer rejected.'
        );
    }

    async runAction(
        action,
        successMessage,
        { resetForm = false, propertyChanged = false } = {}
    ) {
        this.isWorking = true;
        try {
            await action();
            if (resetForm) {
                this.buyerName = '';
                this.amount = undefined;
            }
            this.toast('Success', successMessage, 'success');
            await refreshApex(this.wiredOffersResult);
            if (propertyChanged) {
                await notifyRecordUpdateAvailable([
                    { recordId: this.recordId }
                ]);
            }
        } catch (error) {
            this.toast(
                'Something went wrong',
                reduceErrors(error).join(', '),
                'error'
            );
        } finally {
            this.isWorking = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
